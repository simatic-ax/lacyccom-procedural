USING System.Timer;
USING System.Math;
USING Siemens.Simatic.DistributedIO;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL 
        ReadDriveParamsStates : SINT(
            /// Idle state in FB
            FB_IDLE := SINT#0,
            /// First cycle state in FB
            FB_FIRST_CYCLE := SINT#1,
            /// Allocating a request element in request buffer DB
            FB_ALLOCATE := SINT#2,
            /// State to check if the communication to the drive object can be established
            FB_GET_RESOURCE := SINT#3,
            /// Busy state in FB
            FB_BUSY := SINT#4,
            /// State to return the allocated index
            FB_RELEASE := SINT#5,
            /// Done state in FB
            FB_DONE := SINT#6,
            /// Error state in FB
            FB_ERROR := SINT#7,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord := SINT#8,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord := SINT#9,
            /// State when temporary error occurred
            FB_BUSY_WAIT := SINT#10
        ) := FB_IDLE;
    END_TYPE

    ///==========================================================================================
    /// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///------------------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Engineering: SIMATIC AX
	/// Restrictions: -
	/// Requirements: S7-1200 / S7-1500
	///               FB LAcycCom_ResourceManager is required
	/// Functionality: Reads parameters from a drive object according to the configured dataset 
    ///==========================================================================================
    FUNCTION_BLOCK ReadDriveParams
        {S7.extern = ReadWrite}
        VAR_INPUT
            /// TRUE: Rising edge starts the functionality once
            execute : BOOL;
            /// Count of parameters to read (-1: read all parameter in dataset)
            parameterCount : INT := -1;
            /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
            driveObjectId : INT := -1;
            /// Hardware identifier of the hardware module
            hardwareId : UINT;
        END_VAR
        
        {S7.extern = ReadOnly}
        VAR_OUTPUT
            /// TRUE: Finished reading all parameters
            done : BOOL;
            /// TRUE: FB is not finished and new output values can be expected
            busy : BOOL;
            /// TRUE: Rising edge informs that an error occurred during the execution of the FB
            error : BOOL;
            /// Status identifier
            status : DriveFunctionStatus;
            /// Diagnostics structure
            diagnostics : typeDriveDiagnostics;
        END_VAR
        
        VAR_IN_OUT
            /// Interface for header of request buffer
            requestBufferHeader : typeRequestBufferHeader;
            /// Interface for request buffer
            requestBuffer : ARRAY[*] OF typeRequestBufferElement;
            /// Interface for dataset
            dataset : ARRAY[*] OF typeDriveDatasetRead;
        END_VAR
        
        VAR
            /// TRUE: Indicates that the execute input in the previous cycle was set
            _executeOld : BOOL := FALSE;
            /// Static value for output busy
            _busy : BOOL := FALSE;
            /// Static value for output done
            _done : BOOL := FALSE;
            /// Static value for output error
            _error : BOOL := FALSE;
            /// TRUE: Process is not yet complete
            _cmdBusy : BOOL := FALSE;
            /// TRUE: Data record was transferred
            _cmdDone : BOOL := FALSE;
            /// TRUE: An error occurred during processing
            _cmdError : BOOL := FALSE;
            /// TRUE: Starts OnDelay
            _timerStart : BOOL := FALSE;
            /// Intern hardware identifier of the hardware module
            _hwId : UINT := UINT#0;
            /// Intern identification number of the drive object
            _doId : BYTE := BYTE#16#00;
            /// Reference number of request
            _refNo : BYTE := BYTE#16#00;
            /// TRUE: No resource manager available; FALSE: Resource manager available
            _withoutResourceManager : BOOL := FALSE;
            /// States in the function block state machine
            _fbState : ReadDriveParamsStates := ReadDriveParamsStates#FB_IDLE;
            /// States in the function block during processing (busy state)
            _fbSubState : ReadDriveParamsStates := ReadDriveParamsStates#FB_BUSY_WriteRecord;
            /// Previous state when temporary error occurs
            _fbSubStateOld : ReadDriveParamsStates := ReadDriveParamsStates#FB_BUSY_WriteRecord;
            /// State of the FB when error occurred
            _stateNumber : ReadDriveParamsStates := ReadDriveParamsStates#FB_IDLE;
            /// Static value for output status
            _status : DriveFunctionStatus := DriveFunctionStatus#STATUS_NO_CALL;
            /// Block status or error information
            _subfunctionStatus : WORD := WORD#16#0000;
            /// Error counter of retry request
            _errorCount : UINT := UINT#0;
            /// Allocated element index in the buffer DB
            _allocatedIndex : INT := 0;
            /// Number of parameters in the dataset
            _countOfElements : INT := 0;
            /// Number of parameter at which the error occurred (-1: no parameter with error)
            _firstParameterError : INT := -1;
            /// TRUE: Input execute is set during processing
            _warningRetriggering : BOOL;
            /// Used data record
            _dataRecordNo : DInt;
            /// Lower bound of dataset
            _lowerBoundDataSet : DINT;
            /// Upper bound of dataset
            _upperBoundDataSet : DINT;
            /// Parameter data
            _parameter : ARRAY[0..READ_PARAMETERS_UPPER_LIM] OF typeParameter;
            /// Parameters needed for initialization of request data
            _reqParameterInit : typeParameterAddress := ( attribute := BYTE#16#10, elementNo := BYTE#16#01, parameterNo := UINT#0, index := UINT#0 );
            /// Parameter header for request data
            _reqParameterHeader : typeParameterHeader;
            /// Parameter address for request data
            _reqParameterAddress : ARRAY[0..READ_PARAMETERS_UPPER_LIM] OF typeParameterAddress;
            /// Parameter header for response data
            _respParameterHeader : typeParameterHeader;
            /// Parameter data for response data
            _respParameterData : ARRAY[0..LENGTH_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
            /// WriteRecord command
            _instWriteRecord : WriteRecord;
            /// ReadRecord command
            _instReadRecord : ReadRecord;
            /// OnDelay
            _instOnDelay : OnDelay;
        END_VAR
        
        VAR_TEMP
            // TRUE: Indicates that the execute input was set
            tempExecute : BOOL;
            // TRUE: New data record was received and is valid
            tempCmdValid : BOOL;
            // Temporary status
            tempStatusWord : WORD;
            // Temporary udint variable
            tempUDint : UDINT;
            // Temporary word variable
            tempWord : WORD;
            // Temporary variable of the output parameterCount
            tempParameterCount : INT;
            // Temporary pointer variable
            tempPointer : INT;
            // Temporary loop index variable
            tempIndex : INT;
            // Last element in queue
            tempLastQueueElement : INT;
            // Temporary status of WriteRecord and ReadRecord command
            tempCmdStatus : DWORD;
            // Temporary DWORD variable
            tempDWord : DWORD;
            // Temporary LWORD variable
            tempLWord : LWORD;
            // Temporary empty diagnostics structure
            tempVoidDiagnostics : typeDriveDiagnostics;
            // Temporary empty header structure
            tempVoidHeader : typeParameterHeader;
            // Temporary element of the dataset
            tempActualElement : typeDriveDatasetRead;
            // Temporary record buffer for WriteRecord and ReadRecord instruction
            tempRecord : ARRAY[0..239] OF BYTE;
        END_VAR
        
        VAR CONSTANT
            // No parameter error in response telegram
            NO_PARAMETER_ERROR : INT := -1;
            // All buffer elements are occupied
            ALL_ELEMENTS_OCCUPIED : INT := -1;
            // Maximum count of parameters
            READ_PARAMETERS_UPPER_LIM : INT := 38;
            // Maximum length of telegram for parameter information in BYTE
            LENGTH_PARAMETER_TELEGRAM_UPPER_LIM : INT := 233;
            // Maximum error counter
            MAX_ERROR_COUNT : UINT := UINT#40;
            // Waiting time until next system function block call
            TIMER_TEMP_ERROR : TIME := T#200MS;
            // Timer limit for allocating a request element
            TIMER_ALLOCATION : TIME := T#10S;
            // Maximum drive object number limited by SINAMICS p101
            MAX_DRIVE_OBJECT_NO : INT := 254;
        END_VAR

        tempExecute := execute; 
    
        //----------------------------------------------------------------------
        // Processing
        //----------------------------------------------------------------------
        // Rising edge of execute starts functionality
        IF (tempExecute = TRUE) AND (_executeOld = FALSE) AND (_busy = TRUE) THEN
            // Input execute is set during processing
            _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            _warningRetriggering := TRUE;
            
        ELSIF (tempExecute = TRUE) AND (_executeOld = FALSE) THEN
            // First call
            // Initialisation
            _done := FALSE;
            _busy := TRUE;
            _error := FALSE;
            _countOfElements := 0;
            _allocatedIndex := 0;
            _hwId := UINT#0;
            _subfunctionStatus := WORD#16#0;
            _doId := BYTE#0;
            _dataRecordNo := 0;
            _stateNumber := ReadDriveParamsStates#FB_IDLE;
            _firstParameterError := -1;
            _cmdBusy := FALSE;
            _cmdDone := FALSE;
            _cmdError := FALSE;
            _errorCount := UINT#0;
            _warningRetriggering := FALSE;
            _fbSubState := ReadDriveParamsStates#FB_BUSY_WriteRecord;
            _fbState := ReadDriveParamsStates#FB_FIRST_CYCLE;
            
            _instOnDelay(signal := FALSE,
                         duration := TIMER_ALLOCATION);

            // Initialize boundaries of dataset
            _lowerBoundDataSet := LOWER_BOUND(dataset, 1);
            _upperBoundDataSet := UPPER_BOUND(dataset, 1);
            _countOfElements := TO_INT(GetCountOfElements(_lowerBoundDataSet, _upperBoundDataSet));
        
        // FB is currently inactive  
        ELSIF (tempExecute = FALSE) AND (_busy = FALSE) THEN
            _error := FALSE;
            _busy := FALSE;
            _done := FALSE;
            _fbState := ReadDriveParamsStates#FB_IDLE;
            
            IF ((_status = DriveFunctionStatus#WARN_EXECUTE) AND (execute = FALSE)) OR (_status <> DriveFunctionStatus#WARN_EXECUTE) THEN
                _status := DriveFunctionStatus#STATUS_NO_CALL;
            END_IF;
        
        END_IF; // tempExecute AND statExecuteOld = FALSE
    
        //----------------------------------------------------------------------
        // State Machine
        //----------------------------------------------------------------------
        
        IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
            CASE _fbState OF
                ReadDriveParamsStates#FB_FIRST_CYCLE:  // First cycle state
                        
                    // Clearing the sending buffer
                    _reqParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO READ_PARAMETERS_UPPER_LIM DO
                        _reqParameterAddress[tempIndex] := _reqParameterInit;
                    END_FOR;
                    
                    // Clearing the receive buffer
                    _respParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO LENGTH_PARAMETER_TELEGRAM_UPPER_LIM DO
                        _respParameterData[tempIndex] := BYTE#16#00;
                    END_FOR;
                
                    // Initialization after start       
                    IF driveObjectId < 0 THEN // V1.5
                        _dataRecordNo := DINT#16#B02E; // Base Mode Parameter Access local; doId not relevant
                        _doId := BYTE#0;
                        
                    ELSIF (driveObjectId <= MAX_DRIVE_OBJECT_NO)
                        AND (driveObjectId <> 0)
                    THEN
                        _dataRecordNo := DINT#16#B02F; // Base Mode Parameter Access global
                        _doId := TO_BYTE(driveObjectId);
                        
                    ELSE // V1.5.2 
                        // Wrong drive object ID at input
                        _error := TRUE;
                        _stateNumber := _fbState;
                        _status := DriveFunctionStatus#ERR_INVALID_DRIVE_OBJECT_ID;
                        _fbState := ReadDriveParamsStates#FB_ERROR;
                    END_IF;
                
                    _hwId := hardwareId;
                    tempParameterCount := parameterCount;
                    
                    diagnostics := tempVoidDiagnostics;
                    IF _status = DriveFunctionStatus#WARN_EXECUTE THEN
                        diagnostics.status := _status;
                    END_IF;
                    
                    diagnostics.driveObjectId := TO_SINT(_doId);
                    diagnostics.hardwareId := _hwId;
                    diagnostics.firstParameterError := _firstParameterError; // V1.3.2
                    diagnostics.errorValue := USINT#16#FF; // V1.3.2
                    
                    // Reference number for next request
                    _refNo := TO_BYTE(TO_UINT(_refNo) + UINT#1);
                    _refNo := Max(_refNo, BYTE#16#01);

                    IF _error THEN // V1.5.2: Check if error appeared
                        ;
                    
                    // Next state is depending on the FB mode
                    ELSIF (_withoutResourceManager = FALSE) THEN
                        _status := DriveFunctionStatus#STATUS_ALLOCATE;
                        _fbState := ReadDriveParamsStates#FB_ALLOCATE;
                        
                    ELSE
                        _status := DriveFunctionStatus#STATUS_BUSY;
                        _fbState := ReadDriveParamsStates#FB_BUSY;
                        _fbSubState := ReadDriveParamsStates#FB_BUSY_WriteRecord;
                    END_IF;
                
                    // Calculates the amount of parameters (only if no error occurs)
                    IF (_error = FALSE) THEN
                        // Calculates the count of elements in readDataset if numberOfParameters < 1
                        IF (tempParameterCount < 1) AND
                        (_countOfElements <= READ_PARAMETERS_UPPER_LIM)
                        THEN
                            diagnostics.parameterCount := _countOfElements;
                        ELSIF (tempParameterCount >= 1) AND  // V1.3.2
                        // Check if numberOfParameters <= 39
                        (tempParameterCount <= READ_PARAMETERS_UPPER_LIM + 1) AND
                        (_countOfElements >= tempParameterCount)
                        THEN
                            _countOfElements := tempParameterCount;
                            diagnostics.parameterCount := _countOfElements;
                        ELSE
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_NO_OF_PARAMETERS;
                            _fbState := ReadDriveParamsStates#FB_ERROR;
                        END_IF;
                    END_IF; // IF (statError = FALSE)
                
                ReadDriveParamsStates#FB_ALLOCATE:
                    // Allocation of a request element
                    IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
                        requestBufferHeader.lockBuffer := TRUE;
                        _allocatedIndex := requestBufferHeader.nextFreeElement;
                        requestBuffer[_allocatedIndex].state := BYTE#16#00;
                        requestBuffer[_allocatedIndex].state.%X0 := TRUE;
                        requestBuffer[_allocatedIndex].hardwareId := _hwId;
                        requestBuffer[_allocatedIndex].queueElementNext := -1;
                        _timerStart := FALSE;
                        _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        _fbState := ReadDriveParamsStates#FB_GET_RESOURCE;
                        
                        // Build up queue
                        IF (requestBufferHeader.firstQueueElement >= 0) THEN
                            // Find last queue element 
                            tempIndex := requestBufferHeader.firstQueueElement;
                            WHILE (tempIndex >= 0) DO
                                tempLastQueueElement := tempIndex;
                                tempIndex := requestBuffer[tempIndex].queueElementNext;
                            END_WHILE;
                        
                            // Insert into list after last element
                            requestBuffer[tempLastQueueElement].queueElementNext := _allocatedIndex;
                            requestBuffer[_allocatedIndex].queueElementPrevious := tempLastQueueElement;
                        ELSE
                            // Element is first element in queue
                            requestBufferHeader.firstQueueElement := _allocatedIndex;
                            requestBuffer[_allocatedIndex].queueElementPrevious := -1;
                        END_IF;
                        
                        // Searching for the next free request element
                        FOR tempIndex := requestBufferHeader.bufferLowerBound TO TO_INT(requestBufferHeader.bufferUpperBound) DO
                            IF (requestBuffer[tempIndex].state.%X0 = FALSE) THEN
                                requestBufferHeader.nextFreeElement := tempIndex;
                                EXIT;
                            END_IF;
                            
                            // All request elements are occupied
                            IF (tempIndex = requestBufferHeader.bufferUpperBound) THEN
                                requestBufferHeader.nextFreeElement := ALL_ELEMENTS_OCCUPIED;
                            END_IF;
                        END_FOR;
                        
                        requestBufferHeader.lockBuffer := FALSE;
                        
                    ELSIF (_instOnDelay.output = TRUE) THEN
                        _error := TRUE;
                        _stateNumber := _fbState;
                        _status := DriveFunctionStatus#ERR_ALLOCATION_TIME;
                        _fbState := ReadDriveParamsStates#FB_ERROR;                        
                    ELSE
                        ; // Waiting until lockbit is reset and a request element is available
                    END_IF; // (buffer.lockBuffer = FALSE) AND (buffer.actualWriteIndex >= 0)
                
                    _instOnDelay(signal := _timerStart,
                                 duration := TIMER_ALLOCATION);
                
                    _timerStart := TRUE;
                    IF (_instOnDelay.output = TRUE) THEN
                        _timerStart := FALSE;
                    END_IF;
                
                ReadDriveParamsStates#FB_GET_RESOURCE:
                
                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferheader.bufferUpperBound) THEN
                        _error := TRUE;
                        _stateNumber := _fbState;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _fbState := ReadDriveParamsStates#FB_ERROR;
                    ELSE
                        IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
                            (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
                        THEN
                            // Request was rejected by buffer manager
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_REQUEST_REJECTED;
                            _fbState := ReadDriveParamsStates#FB_ERROR;
                        
                        ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
                            // Request already released
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_RESOURCE_RELEASED;
                            _fbState := ReadDriveParamsStates#FB_ERROR;
                        
                        ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
                            // Element is enabled
                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fbState := ReadDriveParamsStates#FB_BUSY;
                            _fbSubState := ReadDriveParamsStates#FB_BUSY_WriteRecord;
                        
                        ELSE
                            // Element not enabled yet
                            // 
                            _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        END_IF;
                    END_IF;
                
                ReadDriveParamsStates#FB_BUSY:
                
                    IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE) AND
                        (requestBuffer[_allocatedIndex].state.%X3 = FALSE)) OR (_withoutResourceManager = TRUE)
                    THEN
                        CASE _fbSubState OF
                            ReadDriveParamsStates#FB_BUSY_WriteRecord:  // Writing the dataset configuration into the drive object
                            
                                IF (_cmdBusy = FALSE) THEN
                                // Resets WriteRecord command
                                _instWriteRecord(request := FALSE,
                                                 record := tempRecord);
                                
                                // Creating header data
                                _reqParameterHeader.refNo := _refNo; // Telegram reference number
                                _reqParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                                _reqParameterHeader.doId := _doId;  // Drive object identification number
                                _reqParameterHeader.parameterNo := TO_BYTE(_countOfElements);  // Count of parameters
                                
                                    // Copying the dataset into a static variable
                                    FOR tempIndex := 0 TO _countOfElements - 1 DO 
                                        // begin at lower bound of dataset
                                        tempActualElement := dataset[tempIndex + _lowerBoundDataSet];
                    
                                        // write common parameters
                                        _parameter[tempIndex].index := tempActualElement.index;
                                        _parameter[tempIndex].parameterNo := tempActualElement.parameterNumber; 
                                        _reqParameterAddress[tempIndex].index := _parameter[tempIndex].index;  // Subindex of parameter
                                        _reqParameterAddress[tempIndex].parameterNo := _parameter[tempIndex].parameterNo;  // Parameter number   
                                    END_FOR;
                                END_IF; // statCmdBusy = FALSE
                            
                                SerializeParamAddress(header := _reqParameterHeader, address := _reqParameterAddress, buffer := tempRecord);

                                // WriteRecord command
                                _instWriteRecord(request := TRUE,                // Transfer data record
                                                 hardwareId := _hwId,            // ID number of the hardware component
                                                 index := _dataRecordNo,         // Data record number
                                                 length := UINT#0,               // Maximum length of the data record to be transferred in bytes         
                                                 record := tempRecord,           // Data record
                                                 done => _cmdDone,               // Data record was transferred          
                                                 busy => _cmdBusy,               // The writing process is not yet complete
                                                 error => _cmdError,             // An error occurred during the writing process
                                                 status => tempCmdStatus);       // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                            
                            
                                // Error occurred
                                IF (_cmdError = TRUE) AND (_error = FALSE) THEN
                                tempStatusWord.%B0 := tempCmdStatus.%B1;
                                tempStatusWord.%B1 := tempCmdStatus.%B2;
                                
                                    //Temporary command status (80A1, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                                    IF (tempStatusWord = WORD#16#80A1) OR  // Negative acknowledgment when writing to the module
                                        (tempStatusWord = WORD#16#80A7) OR   // DP slave or module is occupied (temporary error)
                                        (tempStatusWord = WORD#16#80B5) OR   // DP slave or module not ready             
                                        (tempStatusWord = WORD#16#80C0) OR   // The data can only be written when the CPU is in STOP mode. Note: this means that writing by the user program is not possible. You can only write the data online with PG/PC.
                                        (tempStatusWord = WORD#16#80C1) OR   // The data of the previous write job on the module for the same data record have not yet been processed by the module.      
                                        (tempStatusWord = WORD#16#80C2) OR   // The module is currently processing the maximum possible number of jobs for a CPU.
                                        (tempStatusWord = WORD#16#80C3) OR   // The required operating resources are currently occupied.
                                        (tempStatusWord = WORD#16#80C4) THEN // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.
                                        
                                        IF (_errorCount >= MAX_ERROR_COUNT) THEN
                                            _error := TRUE;
                                            _stateNumber := _fbSubState;
                                            _subfunctionStatus := tempStatusWord;
                                            _status := DriveFunctionStatus#ERR_WRITERECORD_TEMP_COUNTER;
                                            _fbState := ReadDriveParamsStates#FB_ERROR;
                                        ELSE
                                            _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                            _fbSubStateOld := ReadDriveParamsStates#FB_BUSY_WriteRecord;
                                            _fbSubState := ReadDriveParamsStates#FB_BUSY_WAIT;
                                        END_IF;
                                    ELSE
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _subfunctionStatus := tempStatusWord;
                                        _status := DriveFunctionStatus#ERR_WRITERECORD;
                                        _fbState := ReadDriveParamsStates#FB_ERROR;
                                    END_IF;
                                
                                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) THEN  // Processing completed without errors
                                    _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                    _fbSubState := ReadDriveParamsStates#FB_BUSY_ReadRecord; // WriteRecord completed and continue with ReadRecord        
                                END_IF; // statCmdError = TRUE
                            
                            ReadDriveParamsStates#FB_BUSY_ReadRecord:  // Reading the values from the drive object
                                // Resets ReadRecord command
                                IF (_cmdBusy = FALSE) THEN
                                    _instReadRecord(request := FALSE,
                                                    record := tempRecord);
                                END_IF;
                                
                                _instReadRecord(request := TRUE,            // Transfer data record
                                                hardwareId := _hwId,        // ID number of the hardware component        
                                                index := _dataRecordNo,     // Data record number
                                                maxLength := UINT#0,        // Maximum length in bytes of the data record information to be read
                                                record := tempRecord,       // Destination area for the data record read
                                                valid => tempCmdValid,      // New data record was received and is valid   
                                                busy => _cmdBusy,           // The reading process is not yet complete
                                                error => _cmdError,         // An error occurred during the reading process
                                                status => tempCmdStatus);   // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code      
                                        
                                tempUDint := DeserializeParamResponse(header => _respParameterHeader, response => _respParameterData, buffer := tempRecord);
                                
                                IF tempUDint > UDINT#0 THEN
                                    // Error occurred
                                    IF (_cmdError = TRUE) THEN
                                        // Get the error information from the status information
                                        tempStatusWord.%B0 := tempCmdStatus.%B1;
                                        tempStatusWord.%B1 := tempCmdStatus.%B2;
                                        
                                        //Temporary command status (80A0, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                                        IF (tempStatusWord = WORD#16#80A0) OR  // Negative acknowledgment when reading the module
                                            (tempStatusWord = WORD#16#80A7) OR   // DP slave or module is occupied (temporary error)
                                            (tempStatusWord = WORD#16#80B5) OR   // DP slave or module not ready             
                                            (tempStatusWord = WORD#16#80C0) OR   // The data can only be written when the CPU is in STOP mode. Note: this means that writing by the user program is not possible. You can only write the data online with PG/PC.
                                            (tempStatusWord = WORD#16#80C1) OR   // The data of the previous write job on the module for the same data record have not yet been processed by the module.      
                                            (tempStatusWord = WORD#16#80C2) OR   // The module is currently processing the maximum possible number of jobs for a CPU.
                                            (tempStatusWord = WORD#16#80C3) OR   // The required operating resources are currently occupied.
                                            (tempStatusWord = WORD#16#80C4)
                                        THEN // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.
                                        
                                            IF (_errorCount >= MAX_ERROR_COUNT) THEN
                                                _error := TRUE;
                                                _stateNumber := _fbSubState;
                                                _subfunctionStatus := tempStatusWord;
                                                _status := DriveFunctionStatus#ERR_READRECORD_TEMP_COUNTER;
                                                _fbState := ReadDriveParamsStates#FB_ERROR;
                                            ELSE
                                                _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                                _fbSubStateOld := ReadDriveParamsStates#FB_BUSY_ReadRecord;
                                                // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                                                IF (tempStatusWord = WORD#16#80A0) THEN
                                                    _fbSubStateOld := ReadDriveParamsStates#FB_BUSY_WriteRecord;
                                                END_IF;
                                                _fbSubState := ReadDriveParamsStates#FB_BUSY_WAIT;
                                            END_IF; // statErrorCount >= MAX_ERROR_COUNT
                                        ELSE
                                            _error := TRUE;
                                            _stateNumber := _fbSubState;
                                            _subfunctionStatus := tempStatusWord;
                                            _status := DriveFunctionStatus#ERR_READRECORD;
                                            _fbState := ReadDriveParamsStates#FB_ERROR;
                                        END_IF;
                                        
                                        // Error : Reference number of the request does not match with the response reference number 
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_refNo <> _respParameterHeader.refNo) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_REFERENCE_NO;
                                        _fbState := ReadDriveParamsStates#FB_ERROR;
                                        
                                        // Error : Invalid response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error)  
                                    ELSIF NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01) AND
                                        (_cmdBusy = FALSE) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_RESPONSE_ID;
                                        _fbState := ReadDriveParamsStates#FB_ERROR;
                                        
                                        // Error : The received number of parameters does not match with the requested number of parameters
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_countOfElements <> TO_INT(_respParameterHeader.parameterNo)) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_PARAMETER_NO;
                                        _fbState := ReadDriveParamsStates#FB_ERROR;
                                        
                                        // Error : The drive object does not match with the responsed DO
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_doId <>_respParameterHeader.doId) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                                        _fbState := ReadDriveParamsStates#FB_ERROR;
                                        
                                        // No error occurred during reading parameters
                                    ELSIF (tempCmdValid = TRUE) THEN
                                        // Analyse of the response buffer
                                        tempPointer := 0;
                                        FOR tempIndex := 0 TO _countOfElements - 1 DO
                                            _parameter[tempIndex].format := TO_USINT(_respParameterData[tempPointer]);  // Format of the parameter
                                            
                                            // Format = Error 
                                            IF ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_FLOATING_POINT) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_OCTET_STRING)) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_OCTET_STRING) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_FLOATING_POINT_64)) OR // V1.6.0
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_FLOATING_POINT_64) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_TIME_DIFFERENCE_WO_DATE)) OR // V1.6.0
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_TIME_DIFFERENCE_WO_DATE) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_BYTE)) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_BOOLEAN) AND _parameter[tempIndex].format > DriveValueFormats#FORMAT_ZERO)) // V1.6.0
                                            THEN
                                                // Format = Error, summarize the first and second error byte in a word error variable for each parameter
                                                _parameter[tempIndex].errorValue := TO_USINT(_respParameterData[tempPointer + 3]);
                                                IF (_firstParameterError = NO_PARAMETER_ERROR) THEN
                                                    diagnostics.firstParameterError := tempIndex;
                                                    diagnostics.errorValue := _parameter[tempIndex].errorValue; // V1.3.2
                                                    _firstParameterError := tempIndex;
                                                    _error := TRUE;
                                                    _stateNumber := _fbSubState;
                                                    _status := DriveFunctionStatus#ERR_PARAMETER;
                                                    _fbState := ReadDriveParamsStates#FB_ERROR;
                                                END_IF;
                                                // Points to the next parameter address
                                                tempPointer := tempPointer + 6;
                                            ELSE                      
                                                CASE _parameter[tempIndex].format OF
                                                    DriveValueFormats#FORMAT_INTEGER_8:
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_SINT(_respParameterData[tempPointer + 2]));          
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_SINT(_respParameterData[tempPointer + 2]));
                                                        _parameter[tempIndex].dwordValue := _respParameterData[tempPointer + 2];
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics 

                                                        tempPointer := tempPointer + 4; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_INTEGER_16:
                                                        tempWord.%B0 := _respParameterData[tempPointer + 3];
                                                        tempWord.%B1 := _respParameterData[tempPointer + 2];
                                                        
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_INT(tempWord));        
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_INT(tempWord));
                                                        _parameter[tempIndex].dwordValue := tempWord;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                                        tempPointer := tempPointer + 4; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_INTEGER_32:
                                                        tempDWord.%B0 := _respParameterData[tempPointer + 5];
                                                        tempDWord.%B1 := _respParameterData[tempPointer + 4];
                                                        tempDWord.%B2 := _respParameterData[tempPointer + 3];
                                                        tempDWord.%B3 := _respParameterData[tempPointer + 2];
                                                        
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_DINT(tempDWord));
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_DINT(tempDWord));
                                                        _parameter[tempIndex].dwordValue := tempDWord;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                                        tempPointer := tempPointer + 6; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_UNSIGNED_8, DriveValueFormats#FORMAT_OCTET_STRING: // V1.5 change OCTET_STRING
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_USINT(_respParameterData[tempPointer + 2]));          
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_USINT(_respParameterData[tempPointer + 2]));
                                                        _parameter[tempIndex].dwordValue := _respParameterData[tempPointer + 2];
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics  

                                                        tempPointer := tempPointer + 4; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_UNSIGNED_16:
                                                        tempWord.%B0 := _respParameterData[tempPointer + 3];
                                                        tempWord.%B1 := _respParameterData[tempPointer + 2];

                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_UINT(tempWord));
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_UINT(tempWord));
                                                        _parameter[tempIndex].dwordValue := tempWord;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                                        tempPointer := tempPointer + 4; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_UNSIGNED_32, DriveValueFormats#FORMAT_TIME_DIFFERENCE, DriveValueFormats#FORMAT_TIME_DIFFERENCE_WO_DATE: // V1.5.4: format "TimeDifference without date indication" added
                                                        tempDWord.%B0 := _respParameterData[tempPointer + 5];
                                                        tempDWord.%B1 := _respParameterData[tempPointer + 4];
                                                        tempDWord.%B2 := _respParameterData[tempPointer + 3];
                                                        tempDWord.%B3 := _respParameterData[tempPointer + 2];
                                                                                
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_UDINT(tempDWord));
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_UDINT(tempDWord));
                                                        _parameter[tempIndex].dwordValue := tempDWord;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                                        tempPointer := tempPointer + 6; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_FLOATING_POINT, DriveValueFormats#FORMAT_DOUBLE_WORD:
                                                        tempDWord.%B0 := _respParameterData[tempPointer + 5];
                                                        tempDWord.%B1 := _respParameterData[tempPointer + 4];
                                                        tempDWord.%B2 := _respParameterData[tempPointer + 3];
                                                        tempDWord.%B3 := _respParameterData[tempPointer + 2];
                                                                                
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_REAL(tempDWord));
                                                        _parameter[tempIndex].realValue := TO_REAL(tempDWord);
                                                        _parameter[tempIndex].dwordValue := tempDWord;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                                        tempPointer := tempPointer + 6; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_BYTE:
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_SINT(_respParameterData[tempPointer + 2]));          
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_SINT(_respParameterData[tempPointer + 2]));
                                                        _parameter[tempIndex].dwordValue := _respParameterData[tempPointer + 2];
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics      

                                                        tempPointer := tempPointer + 4; // Points to the next parameter address

                                                    DriveValueFormats#FORMAT_WORD:
                                                        tempWord.%B0 := _respParameterData[tempPointer + 3];
                                                        tempWord.%B1 := _respParameterData[tempPointer + 2];
                                                        
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(TO_SINT(tempWord));
                                                        _parameter[tempIndex].realValue := TO_REAL(TO_SINT(tempWord));
                                                        _parameter[tempIndex].dwordValue := tempWord;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                                        tempPointer := tempPointer + 4; // Points to the next parameter address
                                                    
                                                    DriveValueFormats#FORMAT_FLOATING_POINT_64:
                                                        tempLWord.%B0 := _respParameterData[tempPointer + 9];
                                                        tempLWord.%B1 := _respParameterData[tempPointer + 8];
                                                        tempLWord.%B2 := _respParameterData[tempPointer + 7];
                                                        tempLWord.%B3 := _respParameterData[tempPointer + 6];
                                                        tempLWord.%B4 := _respParameterData[tempPointer + 5];
                                                        tempLWord.%B5 := _respParameterData[tempPointer + 4];
                                                        tempLWord.%B6 := _respParameterData[tempPointer + 3];
                                                        tempLWord.%B7 := _respParameterData[tempPointer + 2];
    
                                                        _parameter[tempIndex].lrealValue := TO_LREAL(tempLWord);
                                                        _parameter[tempIndex].realValue := REAL#0.0;
                                                        _parameter[tempIndex].dwordValue := DWORD#16#0;
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics
    
                                                        tempPointer := tempPointer + 10; // Points to the next paramter address
                                                        
                                                    DriveValueFormats#FORMAT_BOOLEAN:
                                                        IF (_respParameterData[tempPointer + 2] = BYTE#16#00) THEN
                                                            _parameter[tempIndex].lrealValue := LREAL#0.0;
                                                            _parameter[tempIndex].realValue := REAL#0.0;
                                                            _parameter[tempIndex].dwordValue := DWORD#16#0;
                                                        ELSE
                                                            _parameter[tempIndex].lrealValue := LREAL#1.0;
                                                            _parameter[tempIndex].realValue := REAL#1.0;
                                                            _parameter[tempIndex].dwordValue := DWORD#16#1;
                                                        END_IF;
    
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics
                                                        
                                                        tempPointer := tempPointer + 4; // Points to the next parameter address
                                                ELSE
                                                    ;
                                                END_CASE;
                                                
                                            END_IF; // Format = Error
                                        END_FOR; // Analyse of the response buffer
                                        
                                        // Copying parameter data into the dataset
                                        FOR tempIndex := 0 TO _countOfElements - 1 DO
                                            // begin at lower bound of dataset
                                            tempActualElement := dataset[tempIndex + _lowerBoundDataSet];

                                            // copy response into element
                                            tempActualElement.index := _parameter[tempIndex].index;
                                            tempActualElement.parameterNumber := _parameter[tempIndex].parameterNo;
                                            tempActualElement.dwordValue := _parameter[tempIndex].dwordValue;
                                            tempActualElement.realValue := _parameter[tempIndex].realValue;
                                            tempActualElement.lrealValue := _parameter[tempIndex].lrealValue;
                                            tempActualElement.errorValue := _parameter[tempIndex].errorValue;
                                            tempActualElement.format := _parameter[tempIndex].format;

                                            // copy element back to dataset
                                            dataset[tempIndex + _lowerBoundDataSet] := tempActualElement;
                                        END_FOR;

                                        _cmdBusy := FALSE;
                                        _cmdError := FALSE;
                                        
                                        // Next state is depending on the FB mode
                                        IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                                            _status := DriveFunctionStatus#STATUS_RELEASE;
                                            _fbState := ReadDriveParamsStates#FB_RELEASE;
                                        
                                        ELSIF (_error = FALSE) THEN
                                            _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                                            _fbState := ReadDriveParamsStates#FB_DONE;
                                        
                                        END_IF; // statMode = MODE_WITH_BUFFER_MANAGER
                                    END_IF; // statCmdError = TRUE

                                ELSE
                                    _error := TRUE;
                                    _stateNumber := _fbSubState;
                                    _status := DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                                    _fbState := DriveActDeactStates#FB_ERROR;
                                END_IF;
                                
                            ReadDriveParamsStates#FB_BUSY_WAIT:
                                // Timer for temporary errors 
                                _instOnDelay(signal := _timerStart,
                                             duration := TIMER_TEMP_ERROR);
                                
                                _timerStart := TRUE;
                                IF (_instOnDelay.output = TRUE) THEN
                                    _timerStart := FALSE;
                                    _fbSubState := _fbSubStateOld;
                                END_IF;
                                
                            ELSE
                                _error := TRUE;
                                _status := DriveFunctionStatus#ERR_UNDEFINED_SUBSTATE;
                                _stateNumber := _fbState;
                                _fbState := ReadDriveParamsStates#FB_ERROR;
                        END_CASE;
                        
                    ELSE
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
                        _stateNumber := _fbState;
                        _fbState := ReadDriveParamsStates#FB_ERROR;
                    END_IF; // ((buffer.element[statAllocatedIndex].enable = TRUE) AND (statMode = MODE_WITH_BUFFER_MANAGER)) OR statMode = MODE_WITHOUT_BUFFER_MANAGER
                
                ReadDriveParamsStates#FB_RELEASE:
                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _stateNumber := _fbState;
                        _fbState := ReadDriveParamsStates#FB_ERROR;
                        
                    ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
                        requestBufferHeader.lockBuffer := TRUE;
                        IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
                            requestBuffer[_allocatedIndex].state.%X2 := TRUE;
                        ELSE
                            ;
                        END_IF;
                        requestBufferHeader.lockBuffer := FALSE;
                        _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                        _fbState := ReadDriveParamsStates#FB_DONE;
                    END_IF;
                ELSE
                    _error := TRUE;
                    _status := DriveFunctionStatus#ERR_UNDEFINED_STATE;
                    _stateNumber := _fbState;
                    _fbState := ReadDriveParamsStates#FB_ERROR;
            END_CASE;
        
            // If input execute is set during processing
            IF _warningRetriggering = TRUE AND _error = FALSE THEN
                _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            END_IF;
        END_IF;
        
        //----------------------------------------------------------------------
        // Error handling and write outputs
        //----------------------------------------------------------------------
    
        // Edge detection
        _executeOld := tempExecute;
    
        IF (_fbState = ReadDriveParamsStates#FB_ERROR) THEN
            // Release the allocated element when error occurs
            IF (_stateNumber <> ReadDriveParamsStates#FB_FIRST_CYCLE) AND (_stateNumber <> ReadDriveParamsStates#FB_ALLOCATE)
                AND (_busy = TRUE) AND (_withoutResourceManager = FALSE)
            THEN
                IF requestBufferHeader.lockBuffer = FALSE THEN // V1.5.1
                    requestBufferHeader.lockBuffer := TRUE;

                    IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
                        requestBuffer[_allocatedIndex].state.%X2 := TRUE;
                    ELSE
                        ;
                    END_IF;

                    requestBufferHeader.lockBuffer := FALSE;
                
                    // Write diagnostics
                    diagnostics.stateNumber := _stateNumber;
                    diagnostics.subfunctionStatus := _subfunctionStatus;
                    diagnostics.status := _status;
                    _busy := FALSE;
                    _done := FALSE;
                
                END_IF;
                
            ELSE
                // Write diagnostics
                diagnostics.stateNumber := _stateNumber;
                diagnostics.subfunctionStatus := _subfunctionStatus;
                diagnostics.status := _status;
                _busy := FALSE;
                _done := FALSE;
            END_IF;
        
        // FB finished request  
        ELSIF (_fbState = ReadDriveParamsStates#FB_DONE) THEN
        
            // Output for one cycle minimum
            IF (tempExecute = FALSE) AND (_done = TRUE) THEN
                _done := FALSE;
                _status := DriveFunctionStatus#STATUS_NO_CALL;
                _fbState := ReadDriveParamsStates#FB_IDLE;
            ELSE
                _done := TRUE;
                _busy := FALSE;
            END_IF;

            // If input execute is set during processing
            IF _warningRetriggering = TRUE THEN
                _status := DriveFunctionStatus#ERR_AMBIGUOUS_FB_CALL;
                diagnostics.status := _status;
                _error := TRUE;
                _done := FALSE;
            END_IF;
        END_IF;
       
        IF _busy = FALSE OR _error = FALSE
        THEN  // V1.5.1
            error := _error;
            status := _status;
        END_IF;
        
        busy := _busy;
        done := _done;
    END_FUNCTION_BLOCK
END_NAMESPACE
USING System.Timer;
USING System.Math;
USING Siemens.Simatic.DistributedIO;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        WriteDriveParamsStates : SINT (
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
            /// WriteRecord (getting format of parameters) in busy state
            FB_BUSY_WriteRecord_1 := SINT#8,
            /// WriteRecord (changing parameters) in busy state
            FB_BUSY_WriteRecord_2 := SINT#9,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord_1 := SINT#10,
            /// ReadRecord (telegram after writing parameters) in busy state
            FB_BUSY_ReadRecord_2 := SINT#11,
            /// State when temporary error occurred
            FB_BUSY_WAIT := SINT#12
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
	/// Functionality: Writes parameters into a drive object according to the configured dataset
    ///==========================================================================================
    FUNCTION_BLOCK WriteDriveParams
        {S7.Extern = ReadWrite}
        VAR_INPUT
            /// TRUE: Rising edge starts the functionality once
            execute : BOOL;
            /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
            driveObjectId : INT := -1;
            /// Hardware identifier of the hardware module
            hardwareId : UINT;
            /// Count of parameters to write (-1: write all parameter in dataset)
            parameterCount : INT := -1;
        END_VAR

        {S7.Extern = ReadOnly}
        VAR_OUTPUT
            /// TRUE: Finished writing all parameters
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
            dataset : ARRAY[*] OF typeDriveDatasetWrite;
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
            /// Intern identification number of the drive object
            _doId : BYTE := BYTE#16#00;
            /// Intern hardware identifier of the hardware module
            _hwId : UINT := UINT#0;
            /// Reference number of request
            _refNo : BYTE := BYTE#16#00;
            /// Static value for output status
            _status : DriveFunctionStatus;
            /// Block status or error information
            _subfunctionStatus : WORD := WORD#16#0000;
            /// TRUE: No resource manager available; FALSE: Resource manager available
            _withoutResourceManager : BOOL := FALSE;
            /// States in the function block state machine
            _fbState : WriteDriveParamsStates;
            /// States in the function block during processing (busy state)
            _fbSubState : WriteDriveParamsStates := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
            /// Previous state when temporary error occurs
            _fbSubStateOld : WriteDriveParamsStates := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
            /// State of the FB when error occurred
            _stateNumber : WriteDriveParamsStates;
            /// Error counter of retry request
            _errorCount : UINT := UINT#16#0000;
            /// Allocated element index in the buffer DB
            _allocatedIndex : INT := 0;
            /// Number of parameters in the dataset
            _countOfElements : INT := 0;
            /// Number of parameter at which the error occurred (-1: no parameter with error)
            _firstParameterError : INT := -1;
            /// TRUE: Input execute is set during processing
            _warningRetriggering : BOOL;
            /// Used data record
            _dataRecordNo : DINT;
            /// Lower bound of dataset
            _lowerBoundDataSet : DINT;
            /// Upper bound of dataset
            _upperBoundDataSet : DINT;
            /// Parameter data
            _parameter : ARRAY[0..WRITE_PARAMETERS_UPPER_LIM] OF typeParameter;
            /// Parameters needed for initialization of request data
            _reqParameterInit : typeParameterAddress := ( attribute := BYTE#16#10, elementNo := BYTE#16#01, parameterNo := UINT#0, index := UINT#0 );
            /// Parameter header for request data
            _reqParameterHeader : typeParameterHeader;
            /// Parameter address for request data
            _reqParameterAddress : ARRAY[0..WRITE_PARAMETERS_UPPER_LIM] OF typeParameterAddress;
            /// Parameter header for write data
            _reqWriteParameterHeader : typeParameterHeader;
            /// Parameter data for write data
            _reqWriteParameterData : ARRAY[0..LENGTH_WRITE_TELEGRAM_UPPER_LIM] OF BYTE;
            /// Parameter header for response data
            _respParameterHeader : typeParameterHeader;
            /// Parameter data for response data
            _respParameterData : ARRAY[0..LENGTH_READ_TELEGRAM_UPPER_LIM] OF BYTE;
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
            // Temporary udint variable
            tempUDint : UDINT;
            // Temporary dword variable
            tempDWord : DWORD;
            // Temporary lword variable
            tempLWord : LWORD;
            // Temporary empty diagnostics structure
            tempVoidDiagnostics : typeDriveDiagnostics;
            // Temporary empty header structure
            tempVoidHeader : typeParameterHeader;
            // Temporary element of the dataset
            tempActualElement : typeDriveDatasetWrite;
            // Temporary record buffer for WriteRecord and ReadRecord instruction
            tempRecord : ARRAY[0..239] OF BYTE;
        END_VAR

        VAR CONSTANT
            // No parameter error in response telegram
            NO_PARAMETER_ERROR : INT := -1;
            // All buffer elements are occupied
            ALL_ELEMENTS_OCCUPIED : INT := -1;
            // Maximum count of parameters
            WRITE_PARAMETERS_UPPER_LIM : INT := 18;
            // Maximum length of parameter information when using WriteRecord
            LENGTH_WRITE_TELEGRAM_UPPER_LIM : INT := 227;
            // Maximum length of telegram for parameter information in BYTE
            LENGTH_READ_TELEGRAM_UPPER_LIM : INT := 113;
            // Maximum error counter
            MAX_ERROR_COUNT : UINT := UINT#100;
            // Waiting time until next system function block call
            TIMER_TEMP_ERROR : Time := T#200MS;
            // Timer limit for allocating a request element
            TIMER_ALLOCATION : Time := T#10S;
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
            _doId := BYTE#16#0;
            _dataRecordNo := 0;
            _stateNumber := WriteDriveParamsStates#FB_IDLE;
            _firstParameterError := -1;
            _cmdBusy := FALSE;
            _cmdDone := FALSE;
            _cmdError := FALSE;
            _errorCount := UINT#0;
            _warningRetriggering := FALSE;
            _fbSubState := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
            _fbState := WriteDriveParamsStates#FB_FIRST_CYCLE;
            
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
            _fbState := WriteDriveParamsStates#FB_IDLE;
            
            IF (_status = DriveFunctionStatus#WARN_EXECUTE) AND (execute = FALSE) OR (_status <> DriveFunctionStatus#WARN_EXECUTE) THEN
                _status := DriveFunctionStatus#STATUS_NO_CALL;
            END_IF;
        END_IF; // tempExecute AND NOT statExecuteOld
        
        //----------------------------------------------------------------------
        // State Machine
        //----------------------------------------------------------------------
        
        IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
            CASE _fbState OF
                WriteDriveParamsStates#FB_FIRST_CYCLE:  // First cycle state
                        
                    // Clearing the sending read buffer
                    _reqParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO WRITE_PARAMETERS_UPPER_LIM DO
                        _reqParameterAddress[tempIndex] := _reqParameterInit;
                    END_FOR;
                    
                    // Clearing the sending write buffer
                    _reqWriteParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO LENGTH_WRITE_TELEGRAM_UPPER_LIM DO
                        _reqWriteParameterData[tempIndex] := BYTE#16#00;
                    END_FOR;
                    
                    // Clearing the receive buffer
                    _respParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO LENGTH_READ_TELEGRAM_UPPER_LIM DO
                        _respParameterData[tempIndex] := BYTE#16#00;
                    END_FOR;
                    
                    // Initialization after start
                    IF driveObjectId < 0 THEN // V1.5
                        _dataRecordNo := DINT#16#B02E; // Base Mode Parameter Access local; doId not relevant
                        _doId := BYTE#16#0;
                        
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
                        _fbState := WriteDriveParamsStates#FB_ERROR;
                    END_IF;
                    
                    _hwId := hardwareId;
                    tempParameterCount := parameterCount;
                    
                    diagnostics := tempVoidDiagnostics;

                    // Input execute is set during silent operation
                    IF _status = DriveFunctionStatus#WARN_EXECUTE THEN
                        diagnostics.status := _status;
                    END_IF;

                    diagnostics.driveObjectId := TO_SINT(_doId);
                    diagnostics.hardwareId := _hwId;
                    diagnostics.firstParameterError := _firstParameterError; // V1.3.2
                    diagnostics.errorValue := USINT#16#FF; // V1.3.2
                    
                    // Reference number for next request
                    _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
                    _refNo := Max(_refNo, BYTE#16#01);

                    IF _error THEN // V1.5.2: Check if error appeared
                        ;	        
                    // Next state is depending on the FB mode
                    ELSIF (_withoutResourceManager = FALSE) THEN
                        _status := DriveFunctionStatus#STATUS_ALLOCATE;
                        _fbState := WriteDriveParamsStates#FB_ALLOCATE;	        
                    ELSE
                        _status := DriveFunctionStatus#STATUS_BUSY;
                        _fbState := WriteDriveParamsStates#FB_BUSY;
                        _fbSubState := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
                    END_IF; // statMode = MODE_WITH_BUFFER_MANAGER
                    
                    // Calculates the amount of parameters (only if no error occurs)
                    IF (_error = FALSE) THEN
                        // Calculates the count of elements in readDataset if numberOfParameters < 1
                        IF (tempParameterCount < 1) AND
                            (_countOfElements <= WRITE_PARAMETERS_UPPER_LIM)
                        THEN
                            diagnostics.parameterCount := _countOfElements;
                        ELSIF (tempParameterCount >= 1) AND // V1.3.2
                            // Check if numberOfParameters <= 19
                            (tempParameterCount <= WRITE_PARAMETERS_UPPER_LIM) AND
                            (_countOfElements >= tempParameterCount)
                        THEN
                            _countOfElements := tempParameterCount;
                            diagnostics.parameterCount := _countOfElements;           
                        ELSE
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_NO_OF_PARAMETERS;
                            _fbState := WriteDriveParamsStates#FB_ERROR;
                        END_IF;
                    END_IF;

                WriteDriveParamsStates#FB_ALLOCATE:

                    // Allocaetion of a request element
                    IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
                        requestBufferHeader.lockBuffer := TRUE;
                        _allocatedIndex := requestBufferHeader.nextFreeElement;
                        requestBuffer[_allocatedIndex].state := BYTE#16#00;
                        requestBuffer[_allocatedIndex].state.%X0 := TRUE;
                        requestBuffer[_allocatedIndex].hardwareId := _hwId;
                        requestBuffer[_allocatedIndex].queueElementNext := -1;
                        _timerStart := FALSE;
                        _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        _fbState := WriteDriveParamsStates#FB_GET_RESOURCE;
                        
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
                        _fbState := WriteDriveParamsStates#FB_ERROR;
                    ELSE
                        ; // Waiting until lockbit is reset and a request element is available
                    END_IF; // (buffer.lockBuffer = FALSE) AND (buffer.actualWriteIndex >= 0)
                
                    _instOnDelay(signal := _timerStart,
                            duration := TIMER_ALLOCATION);
                    
                    _timerStart := TRUE;
                    IF (_instOnDelay.signal = TRUE) THEN
                        _timerStart := FALSE;
                    END_IF;
                
                WriteDriveParamsStates#FB_GET_RESOURCE: 

                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
                        _error := TRUE;
                        _stateNumber := _fbState;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _fbState := WriteDriveParamsStates#FB_ERROR;
                        
                    ELSE
                        IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
                            (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
                        THEN
                            // Request was rejected by buffer manager
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_REQUEST_REJECTED;
                            _fbState := WriteDriveParamsStates#FB_ERROR;
                        
                        ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
                            // Request already released
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_RESOURCE_RELEASED;
                            _fbState := WriteDriveParamsStates#FB_ERROR;
                        
                        ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
                            // Element is enabled
                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fbState := WriteDriveParamsStates#FB_BUSY;
                            _fbSubState := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
                        
                        ELSE
                            // Element not enabled yet
                            _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        END_IF;
                        
                    END_IF;
                
                WriteDriveParamsStates#FB_BUSY:
                
                    IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE)
                        AND (requestBuffer[_allocatedIndex].state.%X3 = FALSE)) OR (_withoutResourceManager = TRUE)
                    THEN      
                        CASE _fbSubState OF
                            WriteDriveParamsStates#FB_BUSY_WriteRecord_1, WriteDriveParamsStates#FB_BUSY_WriteRecord_2:  // Writing the dataset configuration into the drive object

                                IF (_cmdBusy = FALSE) AND (_fbSubState = WriteDriveParamsStates#FB_BUSY_WriteRecord_1) AND (_error = FALSE) THEN
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
                                        _parameter[tempIndex].index := UINT#0;
                                        _parameter[tempIndex].parameterNo := tempActualElement.parameterNumber;

                                        // write specific parameters from datatype
                                        IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                            _parameter[tempIndex].realValue := tempActualElement.realValue;
                                        ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                            _parameter[tempIndex].dwordValue := tempActualElement.dwordValue;
                                        ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                            _parameter[tempIndex].lrealValue := tempActualElement.lrealValue;
                                        END_IF;

                                        _reqParameterAddress[tempIndex].index := _parameter[tempIndex].index;  // Subindex of parameter
                                        _reqParameterAddress[tempIndex].parameterNo := _parameter[tempIndex].parameterNo;  // Parameter number   
                                    END_FOR;
                                
                                ELSIF (_cmdBusy = FALSE) AND (_fbSubState = WriteDriveParamsStates#FB_BUSY_WriteRecord_2) AND (_error = FALSE) THEN
                                    // Resets WriteRecord command
                                    _instWriteRecord(request := FALSE,
                                                     record := tempRecord);
                                    
                                    tempPointer := 0;
                                    // Creating header data
                                    _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                                    _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                                    _reqWriteParameterHeader.doId := _doId;  // Drive object identification number
                                    _reqWriteParameterHeader.parameterNo := TO_BYTE(_countOfElements);  // Count of parameters
                                    
                                    FOR tempIndex := 0 TO _countOfElements - 1 DO
                                        _reqWriteParameterData[tempPointer] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                                        _reqWriteParameterData[tempPointer + 1] := BYTE#16#01; // No. of elements (for single elements=1) 
                                        
                                        // begin at lower bound of dataset
                                        tempActualElement := dataset[tempIndex + _lowerBoundDataSet];

                                        _parameter[tempIndex].index := tempActualElement.index;
                                        _parameter[tempIndex].parameterNo := tempActualElement.parameterNumber;
                                                        
                                        // Parameter number                               
                                        _reqWriteParameterData[tempPointer + 3] := _parameter[tempIndex].parameterNo.%B0;
                                        _reqWriteParameterData[tempPointer + 2] := _parameter[tempIndex].parameterNo.%B1;
                                        
                                        // Subindex of parameter
                                        _reqWriteParameterData[tempPointer + 5] := _parameter[tempIndex].index.%B0;
                                        _reqWriteParameterData[tempPointer + 4] := _parameter[tempIndex].index.%B1;
                                        
                                        // Points to the next parameter address
                                        tempPointer := tempPointer + 6;
                                    END_FOR;
                                
                                    // Creating parameter address
                                    FOR tempIndex := 0 TO _countOfElements - 1 DO
                                        IF (_parameter[tempIndex].format = DriveValueFormats#FORMAT_ERROR) THEN
                                            _parameter[tempIndex].format := DriveValueFormats#FORMAT_FLOATING_POINT;
                                        END_IF;
                                        
                                        _reqWriteParameterData[tempPointer] := TO_BYTE(_parameter[tempIndex].format); // Format of parameter
                                        _reqWriteParameterData[tempPointer + 1] := BYTE#16#01; // Count of values
                                        
                                        // begin at lower bound of dataset
                                        tempActualElement := dataset[tempIndex + _lowerBoundDataSet];


                                        CASE _parameter[tempIndex].format OF
                                            DriveValueFormats#FORMAT_INTEGER_8:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_SINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_SINT(_parameter[0].lrealValue));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B0;

                                                tempPointer := tempPointer + 4;  // Points to the next parameter address
                                                
                                            DriveValueFormats#FORMAT_INTEGER_16:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_INT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_INT(_parameter[0].lrealValue));
                                                END_IF;

                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B0;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B1;

                                                tempPointer := tempPointer + 4;  // Points to the next parameter address
                                            
                                            DriveValueFormats#FORMAT_INTEGER_32:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_DINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_DINT(_parameter[0].lrealValue));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 5] := tempDWord.%B0;
                                                _reqWriteParameterData[tempPointer + 4] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B2;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B3;
                                                
                                                tempPointer := tempPointer + 6; // Points to the next parameter address
                                                
                                            DriveValueFormats#FORMAT_UNSIGNED_8, DriveValueFormats#FORMAT_OCTET_STRING: // V1.5 change OCTET_STRING:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT(_parameter[0].lrealValue));
                                                END_IF;

                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B0;

                                                tempPointer := tempPointer + 4;  // Points to the next parameter address
                                                
                                            DriveValueFormats#FORMAT_UNSIGNED_16:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_SINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_SINT(_parameter[0].lrealValue));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B0;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B1;

                                                tempPointer := tempPointer + 4;  // Points to the next parameter address
                                                
                                            DriveValueFormats#FORMAT_UNSIGNED_32, DriveValueFormats#FORMAT_TIME_DIFFERENCE:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_UDINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_UDINT(_parameter[0].lrealValue));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 5] := tempDWord.%B0;
                                                _reqWriteParameterData[tempPointer + 4] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B2;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B3;
                                                
                                                tempPointer := tempPointer + 6; // Points to the next parameter address

                                            DriveValueFormats#FORMAT_FLOATING_POINT, DriveValueFormats#FORMAT_DOUBLE_WORD:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(_parameter[0].realValue);
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_LWORD((_parameter[0].lrealValue)));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 5] := tempDWord.%B0;
                                                _reqWriteParameterData[tempPointer + 4] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B2;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B3;
                                                
                                                tempPointer := tempPointer + 6;  // Points to the next parameter address
                                            
                                            DriveValueFormats#FORMAT_BYTE:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT((_parameter[0].lrealValue)));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B0;

                                                tempPointer := tempPointer + 4;  // Points to the next parameter address
                                                
                                            DriveValueFormats#FORMAT_WORD:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT((_parameter[0].lrealValue)));
                                                END_IF;
                                            
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B0;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B1;

                                                tempPointer := tempPointer + 4;  // Points to the next parameter address

                                            DriveValueFormats#FORMAT_FLOATING_POINT_64:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempLword := TO_LWORD(_parameter[0].lrealValue);
                                                END_IF;

                                                _reqWriteParameterData[tempPointer + 9] := tempLWord.%B0;
                                                _reqWriteParameterData[tempPointer + 8] := tempLWord.%B1;
                                                _reqWriteParameterData[tempPointer + 7] := tempLWord.%B2;
                                                _reqWriteParameterData[tempPointer + 6] := tempLWord.%B3;
                                                _reqWriteParameterData[tempPointer + 5] := tempLWord.%B4;
                                                _reqWriteParameterData[tempPointer + 4] := tempLWord.%B5;
                                                _reqWriteParameterData[tempPointer + 3] := tempLWord.%B6;
                                                _reqWriteParameterData[tempPointer + 2] := tempLWord.%B7; 

                                                tempPointer := tempPointer + 10; // Points to the next parameter address

                                            DriveValueFormats#FORMAT_BOOLEAN:
                                                IF (tempActualElement.valueSelector = DatatypeSelector#TYPE_REAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT(_parameter[0].realValue));
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_DWORD) THEN
                                                    tempDWord := _parameter[0].dwordValue;
                                                ELSIF (tempActualElement.valueSelector = DatatypeSelector#TYPE_LREAL) THEN
                                                    tempDWord := TO_DWORD(TO_USINT((_parameter[0].lrealValue)));
                                                END_IF;

                                                IF (tempDWord <> DWORD#16#0) THEN
                                                    tempDWord := DWORD#16#1;
                                                END_IF;

                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B0;

                                                tempPointer := tempPointer + 4; // Points to the next parameter address
                                        ELSE
                                            // clear temp when no format is suitable
                                            tempDWord := DWORD#16#0;
                                            tempLWord := LWORD#16#0;
                                        END_CASE;
                                    END_FOR; // // Creating parameter address
                                END_IF; // statCmdBusy = FALSE AND statParameterConfig = TRUE	            
                                
                                IF (_fbSubState = WriteDriveParamsStates#FB_BUSY_WriteRecord_1) AND (_error = FALSE) THEN
                                    SerializeParamAddress(header := _reqParameterHeader, address := _reqParameterAddress, buffer := tempRecord);

                                    // WriteRecord command
                                    _instWriteRecord(request := TRUE,           // Transfer data record
                                                     hardwareId := _hwId,       // ID number of the hardware component
                                                     index := _dataRecordNo,    // Data record number
                                                     length := UINT#0,          // Maximum length of the data record to be transferred in bytes
                                                     record := tempRecord,      // Data record  
                                                     done => _cmdDone,          // Data record was transferred 
                                                     busy => _cmdBusy,          // The writing process is not yet complete
                                                     error => _cmdError,        // An error occurred during the writing process
                                                     status => tempCmdStatus);  // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                    
                                ELSIF (_fbSubState = WriteDriveParamsStates#FB_BUSY_WriteRecord_2) AND (_error = FALSE) THEN
                                    SerializeParamWrite(header := _reqWriteParameterHeader, data := _reqWriteParameterData, buffer := tempRecord);

                                    // WriteRecord command
                                    _instWriteRecord(request := TRUE,           // Transfer data record
                                                     hardwareId := _hwId,       // ID number of the hardware component
                                                     index := _dataRecordNo,    // Data record number
                                                     length := UINT#0,          // Maximum length of the data record to be transferred in bytes
                                                     record := tempRecord,      // Data record  
                                                     done => _cmdDone,          // Data record was transferred 
                                                     busy => _cmdBusy,          // The writing process is not yet complete
                                                     error => _cmdError,        // An error occurred during the writing process
                                                     status => tempCmdStatus);  // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code  
                                END_IF; 
                                
                                // Error occurred
                                IF (_cmdError = TRUE) AND (_error = FALSE) THEN
                                    // Get the error information from the status information
                                    tempStatusWord.%B0 := tempCmdStatus.%B1;
                                    tempStatusWord.%B1 := tempCmdStatus.%B2;
                                    
                                    // Temporary command status (80A1, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                                    IF (tempStatusWord = WORD#16#80A1) OR  // Negative acknowledgment when writing to the module
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
                                            _status := DriveFunctionStatus#ERR_WRITERECORD_TEMP_COUNTER;
                                            _fbState := WriteDriveParamsStates#FB_ERROR;
                                        ELSE
                                            _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                            _fbSubStateOld := _fbSubState;
                                            _fbSubState := WriteDriveParamsStates#FB_BUSY_WAIT;
                                        END_IF;
                                    ELSE
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _subfunctionStatus := tempStatusWord;
                                        _status := DriveFunctionStatus#ERR_WRITERECORD;
                                        _fbState := WriteDriveParamsStates#FB_ERROR;
                                    END_IF; // Temporary command status (80A1, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                                
                                ELSIF (_cmdBusy = FALSE) AND (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = WriteDriveParamsStates#FB_BUSY_WriteRecord_1) THEN  // Processing completed without errors
                                    _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                    _fbSubState := WriteDriveParamsStates#FB_BUSY_ReadRecord_1; // WriteRecord completed and continue with ReadRecord
                                
                                ELSIF (_cmdBusy = FALSE) AND (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = WriteDriveParamsStates#FB_BUSY_WriteRecord_2) THEN  // Processing completed without errors
                                    _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                    _fbSubState := WriteDriveParamsStates#FB_BUSY_ReadRecord_2; // WriteRecord completed and continue with ReadRecord  
                                    // Clearing the receive buffer
                                    _respParameterHeader := tempVoidHeader;
                                    FOR tempIndex := 0 TO LENGTH_READ_TELEGRAM_UPPER_LIM DO
                                        _respParameterData[tempIndex] := BYTE#16#00;
                                    END_FOR;
                                END_IF; // statCmdError = TRUE
                            
                            WriteDriveParamsStates#FB_BUSY_ReadRecord_1, WriteDriveParamsStates#FB_BUSY_ReadRecord_2:  // Reading the values from the drive object
                                
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
                                    IF (_cmdError = TRUE) AND (_error = FALSE) THEN
                                        // Get the error information from the status information
                                        tempStatusWord.%B0 := tempCmdStatus.%B1;
                                        tempStatusWord.%B1 := tempCmdStatus.%B2;
                                        
                                        // Temporary command status (80A0, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
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
                                                _fbState := WriteDriveParamsStates#FB_ERROR;
                                            ELSE
                                                _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                                _fbSubStateOld := _fbSubState;
                                                // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                                                IF (tempStatusWord = WORD#16#80A0) AND _fbSubState = WriteDriveParamsStates#FB_BUSY_ReadRecord_1 THEN
                                                    _fbSubStateOld := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
                                                ELSIF (tempStatusWord = WORD#16#80A0) AND _fbSubState = WriteDriveParamsStates#FB_BUSY_ReadRecord_2 THEN
                                                    _fbSubStateOld := WriteDriveParamsStates#FB_BUSY_WriteRecord_2;
                                                END_IF;
                                                _fbSubState := WriteDriveParamsStates#FB_BUSY_WAIT;
                                            END_IF;
                                        ELSE
                                            _error := TRUE;
                                            _stateNumber := _fbSubState;
                                            _subfunctionStatus := tempStatusWord;
                                            _status := DriveFunctionStatus#ERR_READRECORD;
                                            _fbState := WriteDriveParamsStates#FB_ERROR;
                                        END_IF; // Temporary command status (80A0, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                                        
                                        // Error : Reference number of the request does not match with the response reference number 
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_refNo <> _respParameterHeader.refNo) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_REFERENCE_NO;
                                        _fbState := WriteDriveParamsStates#FB_ERROR;
                                        
                                        // Error : Invalid response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error; 16#02: writing parameter sucessful; 16#82: writing parameter finished with error)  
                                    ELSIF (_cmdBusy = FALSE) AND
                                        NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01 OR _respParameterHeader.reqId = BYTE#16#02 OR _respParameterHeader.reqId = BYTE#16#82) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_RESPONSE_ID;
                                        _fbState := WriteDriveParamsStates#FB_ERROR;
                                        
                                        // Error : The received number of parameters does not match with the requested number of parameters
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_countOfElements <> TO_INT(_respParameterHeader.parameterNo)) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_PARAMETER_NO;
                                        _fbState := WriteDriveParamsStates#FB_ERROR;
                                        
                                        // Error : The drive object does not match with the responsed DO
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_doId <> _respParameterHeader.doId) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                                        _fbState := WriteDriveParamsStates#FB_ERROR;
                                        
                                        // No error occurred during reading parameters
                                    ELSIF (_cmdBusy = FALSE) AND (tempCmdValid = TRUE) AND (_error = FALSE) THEN
                                        
                                        IF (_fbSubState = WriteDriveParamsStates#FB_BUSY_ReadRecord_1) THEN
                                        
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
                                                    _parameter[tempIndex].errorValue := TO_USINT(_respParameterData[tempPointer + 3]);
                                                    // Points to the next parameter address
                                                    tempPointer := tempPointer + 6;
                                                ELSE
                                                    CASE _parameter[tempIndex].format OF
                                                        DriveValueFormats#FORMAT_INTEGER_8, DriveValueFormats#FORMAT_UNSIGNED_8, DriveValueFormats#FORMAT_BYTE, DriveValueFormats#FORMAT_INTEGER_16, DriveValueFormats#FORMAT_UNSIGNED_16, DriveValueFormats#FORMAT_OCTET_STRING, DriveValueFormats#FORMAT_WORD, DriveValueFormats#FORMAT_BOOLEAN:
                                                            _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostic
                                                            tempPointer := tempPointer + 4; // Points to the next parameter address
                                                        
                                                        DriveValueFormats#FORMAT_INTEGER_32, DriveValueFormats#FORMAT_UNSIGNED_32, DriveValueFormats#FORMAT_TIME_DIFFERENCE, DriveValueFormats#FORMAT_FLOATING_POINT, DriveValueFormats#FORMAT_DOUBLE_WORD:
                                                            _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics
                                                            tempPointer := tempPointer + 6; // Points to the next parameter address

                                                        DriveValueFormats#FORMAT_FLOATING_POINT_64:
                                                            _parameter[tempIndex].errorValue := USINT#16#FF;
                                                            tempPointer := tempPointer + 10;
                                                        ELSE
                                                            ;
                                                    END_CASE;
                                                END_IF; // Format = Error 
                                            END_FOR; // Analyse of the response buffer
                                        
                                            _cmdBusy := FALSE;
                                            _cmdError := FALSE;
                                            _fbState := WriteDriveParamsStates#FB_BUSY;
                                            _fbSubState := WriteDriveParamsStates#FB_BUSY_WriteRecord_2;
                                        ELSE                
                                            // Error occurred during writing process (changing parameter values) 
                                            IF (_respParameterHeader.reqId = BYTE#16#82) THEN  // reqId: 16#82 (Error occurred during writing paramaters)
                                                tempPointer := 0;
                                                
                                                FOR tempIndex := 0 TO _countOfElements - 1 DO
                                                    // Parameter error
                                                    IF (_respParameterData[tempPointer] = TO_BYTE(DriveValueFormats#FORMAT_ERROR)) THEN
                                                        
                                                        _parameter[tempIndex].errorValue := TO_USINT(_respParameterData[tempPointer + 3]); // V1.3.2
                                                        // Save first parameter error in telegram
                                                        IF (_firstParameterError = NO_PARAMETER_ERROR) THEN
                                                            _firstParameterError := tempIndex;
                                                            diagnostics.firstParameterError := _firstParameterError;
                                                            diagnostics.errorValue := _parameter[tempIndex].errorValue; // V1.3.2
                                                            _error := TRUE;
                                                            _stateNumber := _fbSubState;
                                                            _status := DriveFunctionStatus#ERR_PARAMETER;
                                                            _fbState := WriteDriveParamsStates#FB_ERROR;
                                                        END_IF;
                                                        
                                                        tempPointer := tempPointer + 6;  // Points to the next parameter address
                                                        
                                                        // Parameter without errors  
                                                    ELSE
                                                        _parameter[tempIndex].errorValue := USINT#16#FF;
                                                        tempPointer := tempPointer + 2;
                                                    END_IF;

                                                    tempActualElement.parameterNumber := _parameter[tempIndex].parameterNo;
                                                    tempActualElement.index := _parameter[tempIndex].index;
                                                    tempActualElement.dwordValue := _parameter[tempIndex].dwordValue;
                                                    tempActualElement.realValue := _parameter[tempIndex].realValue;
                                                    tempActualElement.lrealValue := _parameter[tempIndex].realValue;
                                                    tempActualElement.errorValue := _parameter[tempIndex].errorValue;
                                                    
                                                    // update dataset element
                                                    dataset[tempIndex + _lowerBoundDataSet] := tempActualElement;
                                                END_FOR;
                                            END_IF; // Error occurred during writing process (changing parameter values)

                                            _cmdBusy := FALSE;
                                            _cmdError := FALSE;
                                            _fbSubState := WriteDriveParamsStates#FB_BUSY_WriteRecord_1;
                                        
                                            // Next state is depending on the FB mode
                                            IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                                                _status := DriveFunctionStatus#STATUS_RELEASE;
                                                _fbState := WriteDriveParamsStates#FB_RELEASE;
                                                
                                            ELSIF (_error = FALSE) THEN
                                                _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                                                _fbState := WriteDriveParamsStates#FB_DONE;
                                            END_IF; // statMode = MODE_WITH_BUFFER_MANAGER
                                        END_IF; // statParameterConfig = TRUE
                                    END_IF; // statCmdError = TRUE
                                ELSE
                                    _error := TRUE;
                                    _stateNumber := _fbSubState;
                                    _status := DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                                    _fbState := DriveActDeactStates#FB_ERROR;
                                END_IF;
                            
                            WriteDriveParamsStates#FB_BUSY_WAIT:
                                // Timer for temporary errors
                                _instOnDelay(signal := _timerStart,
                                             duration := TIMER_TEMP_ERROR);
                                
                                _timerStart := TRUE;
                                IF (_instOnDelay.signal = TRUE) THEN
                                    _timerStart := FALSE;
                                    _fbSubState := _fbSubStateOld;
                                END_IF;
                            
                        ELSE
                            _error := TRUE;
                            _status := DriveFunctionStatus#ERR_UNDEFINED_SUBSTATE;
                            _stateNumber := _fbState;
                            _fbState := WriteDriveParamsStates#FB_ERROR;
                        END_CASE;
                        
                    ELSE
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
                        _stateNumber := _fbState;
                        _fbState := WriteDriveParamsStates#FB_ERROR;
                    END_IF; // ((buffer.element[statAllocatedIndex].enable = TRUE) AND (statMode = MODE_WITH_BUFFER_MANAGER)) OR statMode = MODE_WITHOUT_BUFFER_MANAGER
                
                WriteDriveParamsStates#FB_RELEASE:
                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _stateNumber := _fbState;
                        _fbState := WriteDriveParamsStates#FB_ERROR;
                        
                    ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
                        requestBufferHeader.lockBuffer := TRUE;
                        IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
                            requestBuffer[_allocatedIndex].state.%X2 := TRUE;
                        ELSE
                            ;
                        END_IF;
                        requestBufferHeader.lockBuffer := FALSE;
                        _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                        _fbState := WriteDriveParamsStates#FB_DONE;
                    END_IF;
                
                ELSE
                    _error := TRUE;
                    _status := DriveFunctionStatus#ERR_UNDEFINED_STATE;
                    _stateNumber := _fbState;
                    _fbState := WriteDriveParamsStates#FB_ERROR;
            END_CASE;
        
            // If input execute is set during processing
            IF _warningRetriggering = TRUE AND _error = FALSE THEN
                _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            END_IF;
        
        END_IF; // statBusy = TRUE
        
        //----------------------------------------------------------------------
        // Error handling and write outputs
        //----------------------------------------------------------------------
        
        // Edge detection
        _executeOld := tempExecute;
        
        IF (_fbState = WriteDriveParamsStates#FB_ERROR) THEN
            // Release the allocated element when error occurs
            IF (_stateNumber <> WriteDriveParamsStates#FB_FIRST_CYCLE) AND (_stateNumber <> WriteDriveParamsStates#FB_ALLOCATE)
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
        ELSIF (_fbState = WriteDriveParamsStates#FB_DONE) THEN
        
            // Output for one cycle minimum
            IF (tempExecute = FALSE) AND (_done = TRUE) THEN
                _done := FALSE;
                _status := DriveFunctionStatus#STATUS_NO_CALL;
                _fbState := WriteDriveParamsStates#FB_IDLE;
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
        
        // Write static values to outputs
        IF _busy = FALSE OR _error = FALSE
        THEN  // V1.5.1
            error := _error;
            status := _status;
        END_IF;
        
        busy := _busy;
        done := _done;
    END_FUNCTION_BLOCK
END_NAMESPACE
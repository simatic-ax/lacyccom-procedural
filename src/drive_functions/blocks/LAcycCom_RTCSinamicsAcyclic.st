USING System.Timer;
USING System.Math;
USING Siemens.Simatic.DistributedIO;
USING Siemens.Simatic.Clocks;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        RTCSinamicsAcyclicStates : SINT (
            /// Idle state in FB
            FB_IDLE := SINT#0,
            /// First cycle state in FB
            FB_FIRST_CYCLE := SINT#1,
            /// Allocating a buffer element in request buffer DB
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
            /// Read CPU clock and prepare dataset for acyclic communication
            FB_BUSY_PREPARE := SINT#10,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord := SINT#11,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord := SINT#12,
            /// Waiting state
            FB_BUSY_WAIT := SINT#13
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
	/// Functionality: FB sets the UTC time in SINAMICS drive system (acyclic)
    ///==========================================================================================
    FUNCTION_BLOCK RTCSinamicsAcyclic
        {S7.Extern = ReadWrite}
        VAR_INPUT 
            /// TRUE: Rising edge starts the functionality once
            execute : BOOL;
            /// Hardware identifier of the hardware module
            hardwareId : UINT;
        END_VAR

        {S7.Extern = ReadOnly}
        VAR_OUTPUT 
            /// TRUE: Time synchronization completed successfully
            done : BOOL;
            /// TRUE: FB is not finished and new output values can be expected
            busy : BOOL;
            /// TRUE: Rising edge informs that an error occurred during the execution of the FB
            error : BOOL;
            /// Status identifier
            status : WORD := DriveFunctionStatus#STATUS_NO_CALL;
            /// Diagnostics structure
            diagnostics : typeDriveDiagnostics;
        END_VAR

        VAR_IN_OUT 
            /// Interface for header of request buffer
            requestBufferHeader : typeRequestBufferHeader;
            /// Interface for request buffer
            requestBuffer : ARRAY [*] OF typeRequestBufferElement;
        END_VAR

        VAR 
            /// Static value for output busy
            _busy : BOOL := FALSE;
            /// Static value for output done
            _done : BOOL := FALSE;
            /// Static value for output error
            _error : BOOL := FALSE;
            /// Old value of execute for edge detection
            _executeOld : BOOL := FALSE;
            /// TRUE: Process is not yet complete
            _cmdBusy : BOOL := FALSE;
            /// TRUE: Data record was transferred
            _cmdDone : BOOL := FALSE;
            /// TRUE: An error occurred during processing
            _cmdError : BOOL := FALSE;
            /// TRUE: Starts OnDelay
            _timerStart : BOOL := FALSE;
            /// Reference number of request
            _refNo : BYTE := BYTE#16#00;
            /// Static value for output status
            _status : WORD := DriveFunctionStatus#STATUS_NO_CALL;
            /// Block status or error information
            _subfunctionStatus : WORD := WORD#16#0000;
            /// TRUE: No resource manager available; FALSE: Resource manager available
            _withoutResourceManager : BOOL := FALSE;
            /// State of the FB when error occurred
            _stateNumber : SINT := SINT#0;
            /// States in the function block state machine
            _fbState : SINT := RTCSinamicsAcyclicStates#FB_IDLE;
            /// States in the function block during processing (busy state)
            _fbSubState : SINT := RTCSinamicsAcyclicStates#FB_BUSY_PREPARE;
            /// Previous state when temporary error occurs
            _fbSubStateOld : SINT := RTCSinamicsAcyclicStates#FB_BUSY_PREPARE;
            /// Error counter of retry request
            _errorCount : UInt := UINT#0;
            /// Allocated element index in the buffer DB
            _allocatedIndex : INT := 0;
            /// Number of parameter at which the error occurred (-1: no parameter with error)
            _firstParameterError : INT := -1;
            /// Intern telegram address of the hardware module
            _hardwareId : UINT := UINT#16#0000;
            /// TRUE: CPU clock is already read and preparing complete
            _prepared : BOOL := FALSE;
            /// TRUE: Input execute is set during processing
            _warningRetriggering : BOOL;
            /// Current data and current time-of-day of the CPU clock
            _cpuTime : LDATE_AND_TIME;
            /// Timestamp day
            _timestampDay : LINT;
            /// Timestamp miliseconds
            _timestampMiliseconds : LINT;
            /// Parameter data
            _parameter : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF typeParameter;
            /// Parameter header for write data
            _reqWriteParameterHeader : typeParameterHeader;
            /// Parameter data for write data
            _reqWriteParameterData : ARRAY[0..LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
            /// Parameter header for response data
            _respParameterHeader : typeParameterHeader;
            /// Parameter data for response data
            _respParameterData : ARRAY[0..LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
            /// WriteRecord command
            _instWriteRecord : WriteRecord;
            /// ReadRecord command
            _instReadRecord : ReadRecord;
            /// OnDelay
            _instOnDelay : OnDelay;
        END_VAR

        VAR_TEMP 
            // TRUE: New data record was received and is valid
            tempCmdValid : BOOL;
            // Temporary pointer variable
            tempPointer : INT;
            // Temporary loop index variable
            tempIndex : INT;
            // Temporary result of a system function as word
            tempRetValWord : WORD;
            // Last element in queue
            tempLastQueueElement : INT;
            // Temporary status
            tempStatusWord : WORD;
            // Temporary status of WriteRecord and ReadRecord command
            tempCmdStatus : DWORD;
            // Temporary udint variable
            tempUDint : UDINT;
            // Temporary dword variable
            tempDWord : DWORD;
            // Temporary empty diagnostics structure
            tempVoidDiagnostics : typeDriveDiagnostics;
            // Temporary empty header structure
            tempVoidHeader : typeParameterHeader;
            // Temporary record buffer for WriteRecord and ReadRecord instruction
            tempRecord : ARRAY[0..239] OF BYTE;
        END_VAR

        VAR CONSTANT 
            // Maximum error counter
            MAX_ERROR_COUNT : UINT := UINT#40;
            // No parameter error in response telegram
            NO_PARAMETER_ERROR : INT := -1;
            // Maximum count of parameters
            NO_OF_PARAMETERS_UPPER_LIM : INT := 3;
            // Maximum length of write telegram in BYTE (for 4 parameters)
            LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM : INT := 43;
            // Maximum length of read telegram in BYTE
            LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM : INT := 23;
            // All buffer elements are occupied
            ALL_ELEMENTS_OCCUPIED : INT := -1;
            // Timer limit for allocating a buffer element
            TIMER_ALLOCATION : TIME := T#10S;
            // Waiting time until next system function block call
            TIMER_TEMP_ERROR : TIME := T#100MS;
            // 7305 days = 20 years (between 1.1.1970 and 1.1.1990)
            DATE_OFFSET : UDINT := UDINT#7305;
            // Number of parameters to be written
            COUNT_OF_ELEMENTS : INT := 4;
            // Conversion value from nanoseconds to days
            NS_TO_DAYS : LREAL := LREAL#1.0e+9 * 3600 * 24;
        END_VAR

        // Check if FB is triggered
        IF (execute = TRUE) AND (_executeOld = FALSE) AND (_busy = TRUE) THEN
            // Input execute is set during processing
            _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            _warningRetriggering := TRUE;
            _executeOld := execute;
        
        ELSIF (execute = TRUE) AND (_executeOld = FALSE) THEN
            // First call
            // Initialisation
            _done := FALSE;
            _error := FALSE;
            _status := DriveFunctionStatus#STATUS_FIRST_CALL;
            _allocatedIndex := 0;
            _subfunctionStatus := BYTE#16#0;
            _stateNumber := SINT#0;
            _firstParameterError := -1;
            _cmdBusy := FALSE;
            _cmdDone := FALSE;
            _cmdError := FALSE;
            _errorCount := UINT#0;
            _warningRetriggering := FALSE;
            _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_PREPARE;
            _fbState := RTCSinamicsAcyclicStates#FB_FIRST_CYCLE;
            _error := FALSE;
            _prepared := FALSE;
            
            //-----------------------------------------------------------------------------------
            // Empty and initialize diagnostics
            _hardwareId := hardwareId;
            diagnostics := tempVoidDiagnostics;
            diagnostics.driveObjectId := SINT#0;
            diagnostics.hardwareId := _hardwareId;
            diagnostics.parameterCount := COUNT_OF_ELEMENTS;
            diagnostics.firstParameterError := _firstParameterError; // V1.3.2
            diagnostics.errorValue := USINT#16#FF; // V1.3.2
            
            _instOnDelay(signal := FALSE,
                        duration := TIMER_ALLOCATION);
            
            _busy := TRUE;
            
            // Reset other outputs
            status := DriveFunctionStatus#STATUS_FIRST_CALL;
            
            busy := _busy;
            error := _error;
            
            _executeOld := execute;
        
        // FB is currently inactive
        ELSIF (execute = FALSE) AND (_busy = FALSE) AND
            (_error = TRUE OR _done = TRUE)
        THEN
            _error := FALSE;
            _busy := FALSE;
            _done := FALSE;
            _fbState := RTCSinamicsAcyclicStates#FB_IDLE;
            
            // Write outputs
            status := DriveFunctionStatus#STATUS_NO_CALL;
            busy := _busy;
            done := _done;
            error := _error;
            
            _executeOld := execute;
            RETURN;
        
        // FB is currently executed and not finished
        ELSIF _busy = TRUE THEN
            _executeOld := execute;
        
        // FB finished request
        ELSE
            _executeOld := execute;
            RETURN; // Wait for start of functionality 
        END_IF;
        //----------------------------------------------------------------------------------------------


        IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
            CASE _fbState OF
                RTCSinamicsAcyclicStates#FB_FIRST_CYCLE:  // First cycle state
                
                    // Clearing the sending write buffer
                    _reqWriteParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM DO
                        _reqWriteParameterData[tempIndex] := BYTE#16#00;
                    END_FOR;
                    
                    // Clearing the receive buffer
                    _respParameterHeader := tempVoidHeader;
                    FOR tempIndex := 0 TO LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM DO
                        _respParameterData[tempIndex] := BYTE#16#00;
                    END_FOR;
                    
                    // Initalisation after start
                    FOR tempIndex := 0 TO COUNT_OF_ELEMENTS - 1 DO
                        _parameter[tempIndex].errorValue := USINT#16#FF;
                        _parameter[tempIndex].format := USINT#0;
                        _parameter[tempIndex].index := UINT#0;
                        _parameter[tempIndex].parameterNo := UINT#0;
                        _parameter[tempIndex].dwordValue := DWORD#0;
                        _parameter[tempIndex].realValue := REAL#0.0;
                    END_FOR;
                    
                    // Next state is depending on the FB mode
                    IF (_withoutResourceManager = FALSE) THEN
                        _status := DriveFunctionStatus#STATUS_ALLOCATE;
                        _fbState := RTCSinamicsAcyclicStates#FB_ALLOCATE;
                        
                    ELSE
                        _status := DriveFunctionStatus#STATUS_BUSY;
                        _fbState := RTCSinamicsAcyclicStates#FB_BUSY;
                        _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_PREPARE;
                    END_IF;
                
                RTCSinamicsAcyclicStates#FB_ALLOCATE:
                    // Allocation of a buffer element
                    IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
                        requestBufferHeader.lockBuffer := TRUE;
                        _allocatedIndex := requestBufferHeader.nextFreeElement;
                        requestBuffer[_allocatedIndex].state := BYTE#16#00;
                        requestBuffer[_allocatedIndex].state.%X0 := TRUE;
                        requestBuffer[_allocatedIndex].hardwareId := _hardwareId;
                        requestBuffer[_allocatedIndex].queueElementNext := -1;
                        _timerStart := FALSE;
                        _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        _fbState := RTCSinamicsAcyclicStates#FB_GET_RESOURCE;
                        
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
                        
                        // Searching for the next free buffer element
                        FOR tempIndex := requestBufferHeader.bufferLowerBound TO TO_INT(requestBufferHeader.bufferUpperBound) DO
                            IF (requestBuffer[tempIndex].state.%X0 = FALSE) THEN
                                requestBufferHeader.nextFreeElement := tempIndex;
                                EXIT;
                            END_IF;
                            
                            // All buffer elements are occupied
                            IF (tempIndex = requestBufferHeader.bufferUpperBound) THEN
                                requestBufferHeader.nextFreeElement := ALL_ELEMENTS_OCCUPIED;
                            END_IF;
                        END_FOR;
                        
                        requestBufferHeader.lockBuffer := FALSE;
                        
                    ELSIF (_instOnDelay.output = TRUE) THEN
                        _error := TRUE;
                        _stateNumber := _fbState;
                        _status := DriveFunctionStatus#ERR_ALLOCATION_TIME;
                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                        
                    ELSE
                        ; // Waiting until lockbit is reset and a buffer element is available
                    END_IF; // (buffer.lockBuffer = FALSE) AND (buffer.actualWriteIndex >= 0)
                    
                    _instOnDelay(signal := _timerStart,
                                 duration := TIMER_ALLOCATION);
                    
                    _timerStart := TRUE;
                    IF (_instOnDelay.signal = TRUE) THEN
                        _timerStart := FALSE;
                    END_IF;
                
                RTCSinamicsAcyclicStates#FB_GET_RESOURCE:
                
                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferLowerBound) THEN
                        _error := TRUE;
                        _stateNumber := _fbState;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                        
                    ELSE
                        IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
                            (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
                        THEN
                            // Job was rejected by buffer manager
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_REQUEST_REJECTED;
                            _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                        
                        ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
                            // Job already released
                            _error := TRUE;
                            _stateNumber := _fbState;
                            _status := DriveFunctionStatus#ERR_RESOURCE_RELEASED;
                            _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                            
                        ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
                            // Element is enabled
                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fbState := RTCSinamicsAcyclicStates#FB_BUSY;
                            _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_PREPARE;
                        
                        ELSE
                            // Element not enabled yet
                            // 
                            _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        END_IF;
                        
                    END_IF;
                
                RTCSinamicsAcyclicStates#FB_BUSY:
                
                    IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE)
                        AND (requestBuffer[_allocatedIndex].state.%X3 = FALSE)) OR (_withoutResourceManager = TRUE)
                    THEN
                        CASE _fbSubState OF
                            
                            RTCSinamicsAcyclicStates#FB_BUSY_PREPARE, RTCSinamicsAcyclicStates#FB_BUSY_WriteRecord:  // Preparing datsset; Writing the dataset configuration into the drive object
                                //----------------------------------------------------------------------------------------------           
                                // Prepare state
                                IF NOT _prepared THEN
                                    // Reading CPU clock
                                    tempRetValWord := GetLocalDateTime(_cpuTime); // Reading current date and time of cpu clock
                                
                                    // Error occurred during RD_LOC_T command
                                    IF (tempRetValWord <> WORD#0) AND (tempRetValWord <> WORD#1) THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _subfunctionStatus := tempRetValWord;
                                        _status := DriveFunctionStatus#ERR_GET_LOCAL_DATE_TIME;
                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        RETURN;
                                        
                                    END_IF;
                                
                                    // Creating header data
                                    _refNo := TO_BYTE(TO_UINT(_refNo) + UINT#1);
                                    _refNo := Max(_refNo, BYTE#16#01);
                                    _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                                    _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                                    _reqWriteParameterHeader.doId := BYTE#16#01;  // Drive object identification number of CU
                                    _reqWriteParameterHeader.parameterNo := TO_BYTE(COUNT_OF_ELEMENTS);  // Count of parameters
                                    
                                    _timestampDay := TO_LINT(TO_LWORD(_cpuTime)) / TO_LINT(NS_TO_DAYS);
                                    _timestampMiliseconds := TO_LINT(TO_LWORD(TO_LTOD(_cpuTime))) / LINT#1000000;

                                    // Copying the dataset into a static variable
                                    _parameter[0].index := UINT#0;
                                    _parameter[0].parameterNo := UINT#3100; // RTC time stamp mode
                                    _parameter[0].format := DriveValueFormats#FORMAT_UNSIGNED_16;
                                    _parameter[0].realValue := REAL#1.0;
                                    
                                    _parameter[1].index := UINT#0;
                                    _parameter[1].parameterNo := UINT#3103; // p3103 UTC Synchronizationprocedure
                                    _parameter[1].format := DriveValueFormats#FORMAT_INTEGER_16;
                                    _parameter[1].realValue := 2; // Simple (not exact) set UTC time with p3101
                                    
                                    _parameter[2].index := UINT#1; // Days
                                    _parameter[2].parameterNo := UINT#3101; // RTC UTC time
                                    _parameter[2].format := DriveValueFormats#FORMAT_UNSIGNED_32;
                                    _parameter[2].realValue := TO_REAL(_timestampDay);
                                    // _parameter[2].realValue := TO_REAL(TO_UDINT(TO_DATE(_cpuTime)) + DATE_OFFSET); // RTC time (days); 7305 days = 20 year (between 1.1.1970 and 1.1.1990)
                                    
                                    _parameter[3].index := UINT#0; // ms
                                    _parameter[3].parameterNo := UINT#3101; // RTC UTC time
                                    _parameter[3].format := DriveValueFormats#FORMAT_UNSIGNED_32;
                                    _parameter[3].realValue := TO_REAL(_timestampMiliseconds);
                                    // _parameter[3].realValue := TO_REAL(TO_UDINT(TO_TOD(_cpuTime))); // RTC time (msec)
                                    
                                    // Create telegram body
                                    tempPointer := 0;
                                    FOR tempIndex := 0 TO COUNT_OF_ELEMENTS - 1 DO
                                        _reqWriteParameterData[tempPointer] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                                        _reqWriteParameterData[tempPointer + 1] := BYTE#16#01; // No. of elements (DEC: for single elements=1) 
                                        
                                        // Parameter number
                                        _reqWriteParameterData[tempPointer + 2] := _parameter[tempIndex].parameterNo.%B1;
                                        _reqWriteParameterData[tempPointer + 3] := _parameter[tempIndex].parameterNo.%B0;
                                        
                                        // Subindex of parameter
                                        _reqWriteParameterData[tempPointer + 4] := _parameter[tempIndex].index.%B1;
                                        _reqWriteParameterData[tempPointer + 5] := _parameter[tempIndex].index.%B0;
                                        
                                        tempPointer := tempPointer + 6; // Points to the next parameter address
                                    END_FOR;
                                
                                    FOR tempIndex := 0 TO COUNT_OF_ELEMENTS - 1 DO
                                        // Parameter value(s) 
                                        _reqWriteParameterData[tempPointer] := TO_BYTE(_parameter[tempIndex].format); // Format of parameter
                                        _reqWriteParameterData[tempPointer + 1] := BYTE#16#01; // Count of values
                                        CASE _parameter[tempIndex].format OF
                                            DriveValueFormats#FORMAT_UNSIGNED_16: // 2 Byte
                                                // Values
                                                tempDWord := TO_DWORD(TO_UDINT(_parameter[tempIndex].realValue));
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B0;
                                                tempPointer := tempPointer + 4;  // Points to the next parameter address
                                            
                                            DriveValueFormats#FORMAT_UNSIGNED_32: //4 Byte
                                                // Values    
                                                tempDWord := TO_DWORD(TO_UDINT(_parameter[tempIndex].realValue));
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B3;
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B2;
                                                _reqWriteParameterData[tempPointer + 4] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 5] := tempDWord.%B0;
                                                
                                                tempPointer := tempPointer + 6; // Points to the next parameter address
                                            
                                            DriveValueFormats#FORMAT_INTEGER_16: // 2 Byte
                                                // Values 
                                                tempDWord := TO_DWORD(TO_DINT(_parameter[tempIndex].realValue));
                                                _reqWriteParameterData[tempPointer + 2] := tempDWord.%B1;
                                                _reqWriteParameterData[tempPointer + 3] := tempDWord.%B0;
                                                
                                                tempPointer := tempPointer + 4; // Points to the next parameter address
                                            ELSE
                                                ;
                                        END_CASE;
                                    END_FOR;
                                
                                    _status := DriveFunctionStatus#STATUS_BUSY;
                                    _fbState := RTCSinamicsAcyclicStates#FB_BUSY;
                                    _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_WriteRecord;
                                    
                                    _prepared := TRUE; // Prepare state is complete, immediately go to WriteRecord state
                                END_IF;

                                //----------------------------------------------------------------------------------------------           
                                // WriteRecord state
                                IF (_cmdBusy = FALSE) THEN
                                    // Resets WriteRecord command
                                    _instWriteRecord(request := FALSE,
                                                    record := tempRecord);
                                END_IF; // statCmdBusy = FALSE
                                
                                SerializeParamWrite(header := _reqWriteParameterHeader, data := _reqWriteParameterData, buffer := tempRecord);

                                // WriteRecord command
                                _instWriteRecord(request := TRUE,                   // Transfer data record
                                                hardwareId := _hardwareId,         // ID number of the hardware component
                                                index := DINT#16#B02F,             // Data record number
                                                length := UINT#0,                  // Maximum length of the data record to be transferred in bytes         
                                                record := tempRecord,              // Data record
                                                done => _cmdDone,                  // Data record was transferred          
                                                busy => _cmdBusy,                  // The writing process is not yet complete
                                                error => _cmdError,                // An error occurred during the writing process
                                                status => tempCmdStatus);          // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                
                                // Error occurred
                                IF (_cmdError = TRUE) AND (_error = FALSE) THEN
                                    tempStatusWord.%B0 := tempCmdStatus.%B1;
                                    tempStatusWord.%B1 := tempCmdStatus.%B2;
                                    
                                    // Temporary command status (80A1, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                                    IF (tempStatusWord = WORD#16#80A1) OR  // Negative acknowledgment when writing to the module
                                        (tempStatusWord = WORD#16#80A7) OR  // DP slave or module is occupied (temporary error)
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
                                            _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        
                                        ELSE
                                            _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                            _fbSubStateOld := _fbSubState;
                                            _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_WAIT;
                                        END_IF;
                                        
                                    ELSE
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _subfunctionStatus := tempStatusWord;
                                        _status := DriveFunctionStatus#ERR_WRITERECORD;
                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                    END_IF;
                                
                                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = RTCSinamicsAcyclicStates#FB_BUSY_WriteRecord) THEN
                                    _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                    _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_ReadRecord; // WriteRecord completed and continue with ReadRecord
                                
                                END_IF; // statCmdError = TRUE
                                
                            RTCSinamicsAcyclicStates#FB_BUSY_ReadRecord:  // Reading the values from the drive object
                                // Resets ReadRecord command
                                
                                IF (_cmdBusy = FALSE) THEN
                                    _instReadRecord(request := FALSE,
                                                    record := tempRecord);
                                END_IF; 
                                
                                _instReadRecord(request := TRUE,                        // Transfer data record
                                                hardwareId := _hardwareId,              // ID number of the hardware component        
                                                index := DINT#16#B02F,                       // Data record number
                                                maxLength := UINT#0,                    // Maximum length in bytes of the data record information to be read
                                                record := tempRecord,                   // Destination area for the data record read 
                                                valid => tempCmdValid,                  // New data record was received and is valid   
                                                busy => _cmdBusy,                       // The reading process is not yet complete
                                                error => _cmdError,                     // An error occurred during the reading process
                                                status => tempCmdStatus);               // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code 

                                tempUDint := DeserializeParamResponse(header => _respParameterHeader, response => _respParameterData, buffer := tempRecord);
                                
                                IF tempUDint > UDINT#0 THEN
                                    // Error occurred
                                    IF (_cmdError = TRUE) THEN
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
                                                _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                                
                                            ELSE
                                                _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                                _fbSubStateOld := _fbSubState;
                                                // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                                                IF (tempStatusWord = WORD#16#80A0) THEN
                                                _fbSubStateOld := RTCSinamicsAcyclicStates#FB_BUSY_WriteRecord;
                                                END_IF;
                                                _fbSubState := RTCSinamicsAcyclicStates#FB_BUSY_WAIT;
                                            END_IF; // statErrorCount >= MAX_ERROR_COUNT
                                        
                                        ELSE
                                            _error := TRUE;
                                            _stateNumber := _fbSubState;
                                            _subfunctionStatus := tempStatusWord;
                                            _status := DriveFunctionStatus#ERR_READRECORD;
                                            _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        END_IF;
                                        
                                        // Error : Reference number of the request does not match with the response reference number 
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_refNo <> _respParameterHeader.refNo) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_REFERENCE_NO;
                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        
                                        // Error : Wrong response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error)  
                                    ELSIF NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01 OR _respParameterHeader.reqId = BYTE#16#02 OR _respParameterHeader.reqId = BYTE#16#82) AND
                                        (_cmdBusy = FALSE) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_RESPONSE_ID;
                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        
                                        // Error : The received number of parameters does not match with the requested number of parameters
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (TO_INT(_respParameterHeader.parameterNo) <> COUNT_OF_ELEMENTS) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_PARAMETER_NO;
                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        
                                        // Error : The drive object does not match with the responsed DO
                                    ELSIF (_cmdBusy = FALSE) AND
                                        (_respParameterHeader.doId <> BYTE#1) AND
                                        (tempCmdValid = TRUE)
                                    THEN
                                        _error := TRUE;
                                        _stateNumber := _fbSubState;
                                        _status := DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                        
                                        // No error occurred during reading parameters
                                    ELSIF (_cmdBusy = FALSE) AND (tempCmdValid = TRUE) AND (_error = FALSE) THEN
                                        // Analyse of the response buffer
                                        
                                        // Error occurred during writing process (changing parameter values) 
                                        IF (_respParameterHeader.reqId = BYTE#16#82) THEN  // reqId: 16#82 (Error occurred during writing paramaters)
                                            tempPointer := 0;
                                            
                                            FOR tempIndex := 0 TO COUNT_OF_ELEMENTS - 1 DO
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
                                                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                                                    END_IF;
                                                    
                                                    tempPointer := tempPointer + 6;  // Points to the next parameter address
                                                
                                                // Parameter without errors  
                                                ELSE
                                                    _parameter[tempIndex].errorValue := USINT#16#FF;
                                                    tempPointer := tempPointer + 2;
                                                END_IF;
                                                
                                            END_FOR;
                                        END_IF; // Error occurred during writing process (changing parameter values)
                                        
                                        // Next state is depending on the FB mode
                                        IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                                            _status := DriveFunctionStatus#STATUS_RELEASE;
                                            _fbState := RTCSinamicsAcyclicStates#FB_RELEASE;
                                        
                                        ELSIF (_withoutResourceManager = TRUE) AND (_error = FALSE) THEN
                                            _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                                            _fbState := RTCSinamicsAcyclicStates#FB_DONE;
                                        
                                        END_IF; // statMode = MODE_WITH_BUFFER_MANAGER
                                    END_IF; // statCmdError = TRUE
                                ELSE
                                    _error := TRUE;
                                    _stateNumber := _fbSubState;
                                    _status := DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                                    _fbState := DriveActDeactStates#FB_ERROR;
                                END_IF;           
                                
                            RTCSinamicsAcyclicStates#FB_BUSY_WAIT:
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
                            _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                        END_CASE;
                        
                    ELSE
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
                        _stateNumber := _fbState;
                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                    END_IF; // ((buffer.element[statAllocatedIndex].enable = TRUE) AND (statMode = MODE_WITH_BUFFER_MANAGER)) OR statMode = MODE_WITHOUT_BUFFER_MANAGER
                
                RTCSinamicsAcyclicStates#FB_RELEASE:
                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _stateNumber := _fbState;
                        _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
                        
                    ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
                        requestBufferHeader.lockBuffer := TRUE;
                        IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
                            requestBuffer[_allocatedIndex].state.%X2 := TRUE;
                        ELSE
                            ;
                        END_IF;
                        requestBufferHeader.lockBuffer := FALSE;
                        _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                        _fbState := RTCSinamicsAcyclicStates#FB_DONE;
                    END_IF;
                
                ELSE
                    _error := TRUE;
                    _status := DriveFunctionStatus#ERR_UNDEFINED_STATE;
                    _stateNumber := _fbState;
                    _fbState := RTCSinamicsAcyclicStates#FB_ERROR;
            END_CASE;
        
            // If input execute is set during processing
            IF _warningRetriggering = TRUE AND _error = FALSE THEN
                _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            END_IF;
        
        END_IF;

        //----------------------------------------------------------------------------------------------
        // Write outputs and error handling
        //----------------------------------------------------------------------------------------------

        // Error occurred in request
        IF (_fbState = RTCSinamicsAcyclicStates#FB_ERROR) THEN
        
            // Release the allocated element when error occurs
            IF (_stateNumber <> RTCSinamicsAcyclicStates#FB_FIRST_CYCLE) AND (_stateNumber <> RTCSinamicsAcyclicStates#FB_ALLOCATE)
                AND (_busy = TRUE) AND (_withoutResourceManager = FALSE)
            THEN
                IF requestBufferHeader.lockBuffer = FALSE THEN  // V1.5.1
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
        
        // Request finished
        ELSIF (_fbState = RTCSinamicsAcyclicStates#FB_DONE) THEN
        
            // Output for one cycle minimum
            IF (execute = FALSE) AND (_done = TRUE) THEN
                _done := FALSE;
                _status := DriveFunctionStatus#STATUS_NO_CALL;
                _fbState := RTCSinamicsAcyclicStates#FB_IDLE;
                
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
        //----------------------------------------------------------------------------------------------
    END_FUNCTION_BLOCK
END_NAMESPACE
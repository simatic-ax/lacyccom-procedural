USING System.Timer;
USING Siemens.Simatic.DistributedIO;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_ReadDriveSingleParamStates : SINT (
      FB_IDLE := SINT#0,   // Idle state in FB
      FB_FIRST_CYCLE := SINT#1,   // First cycle state in FB
      FB_ALLOCATE := SINT#2,   // Allocating a request element in request buffer DB
      FB_GET_RESOURCE := SINT#3,   // State to check if the communication to the drive object can be established
      FB_BUSY := SINT#4,   // Busy state in FB
      FB_RELEASE := SINT#5,   // State to return the allocated index
      FB_DONE := SINT#6,   // Done state in FB
      FB_ERROR := SINT#7,   // Error state in FB
      FB_BUSY_WriteRecord := SINT#8,   // WriteRecord in busy state
      FB_BUSY_ReadRecord := SINT#9,   // ReadRecord in busy state
      FB_BUSY_WAIT := SINT#10   // State when temporary error occurred
    ) := FB_IDLE;
  END_TYPE

  ///------------------------------------------------------------------------------------------
  /// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///------------------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Tested with: S7-1513-1 PN
	/// Engineering: SIMATIC AX
	/// Restrictions: ---
	/// Requirements: S7-1200 / S7-1500
	///               FB LAcycCom_ResourceManager is required
	/// Functionality: Reads one parameter from a drive object
  ///------------------------------------------------------------------------------------------
  FUNCTION_BLOCK LAcycCom_ReadDriveSingleParam
    {S7.Extern = ReadWrite}
    VAR_INPUT
      execute : BOOL;   /// TRUE: Rising edge starts the functionality once
      driveObjectId : INT := -1;   /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
      hardwareId : UINT;   /// Hardware identifier of the hardware module
      parameterNumber : UINT;   /// Number of the parameter
      index : UINT := UINT#0;   /// Parameter index
    END_VAR

    {S7.Extern = ReadOnly}
    VAR_OUTPUT
      done : BOOL;   /// TRUE: Finished reading the parameter
      busy : BOOL;   /// TRUE: FB is not finished and new output values can be expected
      error : BOOL;   /// TRUE: Rising edge informs that an error occurred during the execution of the FB
      status : LAcycCom_DriveFunctionStatus;   /// Status identifier
      realValue : REAL := REAL#0.0;   /// Parameter value (real value)
      dWordValue : DWORD := DWORD#16#0000_0000;   /// Parameter value (dword value)
      errorValue : BYTE := BYTE#16#FF;   /// Error number (16#FF: no error; else: see error list)
      diagnostics : LAcycCom_typeDriveDiagnostics;   /// Diagnostics structure
    END_VAR

    VAR_IN_OUT
      requestBufferHeader : LAcycCom_typeRequestBufferHeader;   /// Interface for header of request buffer
      requestBuffer : ARRAY[*] OF LAcycCom_typeRequestBufferElement;   /// Interface for request buffer
    END_VAR

    VAR
      _executeOld : BOOL := FALSE;   /// TRUE: Indicates that the execute input in the previous cycle was set
      _busy : BOOL := FALSE;   /// Static value for output busy
      _done : BOOL := FALSE;   /// Static value for output done
      _error : BOOL := FALSE;   /// Static value for output error
      _cmdBusy : BOOL := FALSE;   /// TRUE: Process is not yet complete
      _cmdDone : BOOL := FALSE;   /// TRUE: Data record was transferred
      _cmdError : BOOL := FALSE;   /// TRUE: An error occurred during processing
      _timerStart : BOOL := FALSE;   /// TRUE: Starts OnDelay
      _hwId : UINT := UINT#0;   /// Intern hardware identifier of the hardware module
      _doId : BYTE := BYTE#16#00;   /// Intern identification number of the drive object
      _refNo : BYTE := BYTE#16#00;   /// Reference number of request
      _withoutResourceManager : BOOL := FALSE;   /// TRUE: No resource manager available; FALSE: Resource manager available
      _fbState : LAcycCom_ReadDriveSingleParamStates;   /// States in the function block state machine
      _fbSubState : LAcycCom_ReadDriveSingleParamStates := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;   /// States in the function block during processing (busy state)
      _fbSubStateOld : LAcycCom_ReadDriveSingleParamStates := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;   /// Previous state when temporary error occurs
      _stateNumber : LAcycCom_ReadDriveSingleParamStates;   /// State of the FB when error occurred
      _status : LAcycCom_DriveFunctionStatus;   /// Static value for output status
      _subfunctionStatus : WORD := WORD#16#0000;   /// Block status or error information
      _errorCount : UINT := UINT#16#0000;   /// Error counter of retry request
      _parameterNumber : UINT := UINT#0;   /// Static value for input parameterNumber
      _parameterIndex : UINT := UINT#0;   /// Static value for input parameterIndex
      _allocatedIndex : INT := 0;   /// Allocated element index in the buffer DB
      _firstParameterError : INT := -1;   /// Number of parameter at which the error occurred (-1: no parameter with error)
      _warningRetriggering : BOOL;   /// TRUE: Input execute is set during processing
      _dataRecordNo : DInt;   /// Used data record
      _parameter : ARRAY[0..READ_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameter;   /// Parameter dataset
      _reqParameterHeader : LAcycCom_typeParameterHeader;   /// Request header telegram
      _reqParameterAddress: ARRAY[0..READ_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameterAddress;   /// Request address telegram
      _reqParameterInit : LAcycCom_typeParameterAddress := ( attribute := BYTE#16#10, elementNo := BYTE#16#01, parameterNo := UINT#0, index := UINT#0 );   /// Initialisation of the parameter dataset
      _respParameterHeader : LAcycCom_typeParameterHeader;   /// Response header telegram
      _respParameterData : ARRAY[0..LENGTH_PARAMETER_TELEGRAM_UPPER_LIM] of BYTE;  // Response telegram data
      _instWriteRecord : WriteRecord;   /// WriteRecord command
      _instReadRecord : ReadRecord;   /// ReadRecord command
      _instOnDelay : OnDelay;   /// OnDelay
    END_VAR

    VAR_TEMP  
      tempExecute : BOOL;   // TRUE: Indicates that the execute input was set
      tempCmdValid : BOOL;   // TRUE: New data record was received and is valid
      tempCmdStatus : DWORD;   // Temporary status of WriteRecord and ReadRecord command
      tempStatusWord : WORD;   // Temporary status
      tempUDint : UDINT;   // Temporary udint variable
      tempWord : WORD;   // Temporary word variable
      tempIndex : INT;   // Temporary loop index variable
      tempLastQueueElement : INT;   // Last element in queue
      tempDWord : DWORD;   // Temporary DWord variable
      tempVoidDiagnostics : LAcycCom_typeDriveDiagnostics;   // Temporary empty diagnostics structure
      tempVoidHeader : LAcycCom_typeParameterHeader;   // Temporary empty header structure
      tempRecord : ARRAY[0..239] OF BYTE;   // Temporary record buffer for WriteRecord and ReadRecord instruction
    END_VAR

    VAR CONSTANT
      NO_PARAMETER_ERROR : INT := -1;   // No parameter error in response telegram
      ALL_ELEMENTS_OCCUPIED : INT := -1;   // All buffer elements are occupied
      READ_PARAMETERS_UPPER_LIM : INT := 0;   // Maximum count of parameters
      LENGTH_PARAMETER_TELEGRAM_UPPER_LIM : INT := 5;   // Maximum length of telegram for parameter information in Byte
      MAX_ERROR_COUNT : UINT := UINT#40;   // Maximum error counter
      TIMER_TEMP_ERROR : TIME := T#200MS;   // Waiting time until next system function block call
      TIMER_ALLOCATION : TIME := T#10S;   // Timer limit for allocating a request element
      MAX_DRIVE_OBJECT_NO : INT := 254;   // Maximum drive object number limited by SINAMICS p101
    END_VAR
    
    //----------------------------------------------------------------------
    // Processing
    //----------------------------------------------------------------------
    // Rising edge of execute starts functionality
    IF (execute = TRUE) AND (_executeOld = FALSE) AND (_busy = TRUE) THEN
      // Input execute is set during processing
      _status := LAcycCom_DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
      _warningRetriggering := TRUE;

    ELSIF (execute = TRUE) AND (_executeOld = FALSE) THEN
      // First call
      // Initialisation
      _done := FALSE;
      _busy := TRUE;
      _error := FALSE;
      _allocatedIndex := 0;
      _hwId := UINT#0;
      _subfunctionStatus := WORD#16#0;
      _doId := BYTE#0;
      _dataRecordNo := 0;
      _stateNumber := SINT#0;
      _firstParameterError := -1;
      _cmdBusy := FALSE;
      _cmdDone := FALSE;
      _cmdError := FALSE;
      _errorCount := UINT#0;
      _warningRetriggering := FALSE;
      _fbSubState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;
      _fbState := LAcycCom_ReadDriveSingleParamStates#FB_FIRST_CYCLE;
      // V1.3.2. Reset outputs at rising edge
      realValue := REAL#0.0;
      dWordValue := DWORD#16#0;
      errorValue := BYTE#16#FF;
      
      _instOnDelay(signal := FALSE,
                   duration := TIMER_ALLOCATION);
      
      // FB is currently inactive  
    ELSIF (execute = FALSE) AND (_busy = FALSE) AND
      (_error = TRUE OR _done = TRUE)
    THEN
      // IF statError THEN
        // Reset outputs
        realValue := REAL#0.0;
        dWordValue := DWORD#16#0;
        errorValue := BYTE#16#FF;
      // END_IF;
      
      _error := FALSE;
      _busy := FALSE;
      _done := FALSE;
      _fbState := LAcycCom_ReadDriveSingleParamStates#FB_IDLE;
      _status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
    END_IF; // #execute AND #statExecuteOld = FALSE
    
    //----------------------------------------------------------------------
    // State Machine
    //----------------------------------------------------------------------
    
    IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
      CASE _fbState OF
        LAcycCom_ReadDriveSingleParamStates#FB_FIRST_CYCLE:  // First cycle state
          
          // Clearing the sending buffer
          _reqParameterHeader := tempVoidHeader;
          _reqParameterAddress[tempIndex] := _reqParameterInit;
          
          // Clearing the receive buffer
          _reqParameterHeader := tempVoidHeader;
          FOR tempIndex := 0 TO LENGTH_PARAMETER_TELEGRAM_UPPER_LIM DO
            _respParameterData[tempIndex] := BYTE#16#00;
          END_FOR;
          
          // Initialization after start
          IF driveObjectId < 0 THEN // V1.5
            _dataRecordNo := DINT#16#B02E; // Base Mode Parameter Access local; doId not relevant
            _doId := BYTE#0;
            
          ELSIF (driveObjectId <= MAX_DRIVE_OBJECT_NO)
            AND (driveObjectId <> 0)
          THEN // V1.5.2
            _dataRecordNo := 47; // Data record 47; Base Mode Parameter Access global
            _doId := TO_BYTE(driveObjectId);
            
          ELSE // V1.5.2 
            // Wrong drive object ID at input
            _error := TRUE;
            _stateNumber := _fbState;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_DRIVE_OBJECT_ID;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
          END_IF;
          
          _hwId := hardwareId;
          _parameterNumber := parameterNumber;
          _parameterIndex := index;
          
          diagnostics := tempVoidDiagnostics;
          diagnostics.driveObjectId := TO_SINT(_doId);
          diagnostics.hardwareId := _hwId;
          diagnostics.parameterCount := 1;
          diagnostics.firstParameterError := _firstParameterError; // V1.3.2
          diagnostics.errorValue := BYTE#16#FF; // V1.3.2
          
          // Reference number for next request
          _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
          
          IF _error THEN // V1.5.2: Check if error appeared
            ;
          // Next state is depending on the FB mode
          ELSIF (_withoutResourceManager = FALSE) THEN
            _status := LAcycCom_DriveFunctionStatus#STATUS_ALLOCATE;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ALLOCATE;
            
          ELSE
            _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY;
            _fbSubState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;
          END_IF;
    
        LAcycCom_ReadDriveSingleParamStates#FB_ALLOCATE:
          // Allocation of a request element
          IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
            requestBufferHeader.lockBuffer := TRUE;
            _allocatedIndex := requestBufferHeader.nextFreeElement;
            requestBuffer[_allocatedIndex].state := BYTE#16#00;
            requestBuffer[_allocatedIndex].state.%X0 := TRUE;
            requestBuffer[_allocatedIndex].hardwareId := _hwId;
            requestBuffer[_allocatedIndex].queueElementNext := -1;
            _timerStart := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_GET_RESOURCE;
            
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
            _status := LAcycCom_DriveFunctionStatus#ERR_ALLOCATION_TIME;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
            
          ELSE
            ; // Waiting until lockbit is reset and a request element is available
          END_IF; // (#buffer.lockBuffer = FALSE) AND (#buffer.actualWriteIndex >= 0)
          
          _instOnDelay(signal := _timerStart,
                       duration := TIMER_ALLOCATION);
          
          _timerStart := TRUE;
          IF (_instOnDelay.output = TRUE) THEN
            _timerStart := FALSE;
          END_IF;
          
        LAcycCom_ReadDriveSingleParamStates#FB_GET_RESOURCE:
          
          // Check buffer index for correctness
          IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _stateNumber := _fbState;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
            
          ELSE
            IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
              (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
            THEN
              // Request was rejected by buffer manager
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_REQUEST_REJECTED;
              _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
              
            ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
              // Request already released
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_RESOURCE_RELEASED;
              _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
              
            ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
              // Element is enabled
              _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
              _fbState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY;
              _fbSubState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;
              
            ELSE
              // Element not enabled yet
              // 
              _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            END_IF;
            
          END_IF;
          
        LAcycCom_ReadDriveSingleParamStates#FB_BUSY:
          IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE) AND
            (requestBuffer[_allocatedIndex].state.%X3 = FALSE)) OR
            (_withoutResourceManager = TRUE)
          THEN
            
            CASE _fbSubState OF
              LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord:  // Writing the dataset configuration into the drive object
                
                IF (_cmdBusy = FALSE) THEN
                  // Resets WriteRecord command
                  _instWriteRecord(request := FALSE,
                                   record := tempRecord);
                  
                  // Creating header data
                  _reqParameterHeader.refNo := _refNo; // Telegram reference number
                  _reqParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                  _reqParameterHeader.doId := _doId;  // Drive object identification number
                  _reqParameterHeader.parameterNo := BYTE#16#01;  // Count of parameters
                  
                  // Copying the dataset into a static variable (tempLoopIndex is always zero here since there is only one single element in the array)
                  _parameter[tempIndex].index := _parameterIndex;
                  _parameter[tempIndex].parameterNo := _parameterNumber;
                  _reqParameterAddress[tempIndex].parameterNo := _parameter[tempIndex].parameterNo;  // Parameter number    
                  _reqParameterAddress[tempIndex].index := _parameter[tempIndex].index;  // Subindex of parameter                  
                END_IF; // statCmdBusy = FALSE
                
                SerializeParamAddress(_reqParameterHeader, _reqParameterAddress, tempRecord);

                // WriteRecord command
                _instWriteRecord(request := TRUE, // Transfer data record
                                 hardwareId := _hwId, // ID number of the hardware component
                                 index := _dataRecordNo, // Data record number
                                 length := UINT#0, // Maximum length of the data record to be transferred in bytes
                                 done => _cmdDone, // Data record was transferred
                                 busy => _cmdBusy, // The writing process is not yet complete
                                 error => _cmdError, // An error occurred during the writing process
                                 status => tempCmdStatus, // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                 record := tempRecord); // Data record
                
                // Error occurred
                IF (_cmdError = TRUE) AND (_error = FALSE) THEN
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
                    (tempStatusWord = WORD#16#80C4) THEN // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.
                    
                    IF (_errorCount >= MAX_ERROR_COUNT) THEN
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _subfunctionStatus := tempStatusWord;
                      _status := LAcycCom_DriveFunctionStatus#ERR_WRITERECORD_TEMP_COUNTER;
                      _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                    ELSE
                      _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                      _fbSubStateOld := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;
                      _fbSubState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WAIT;
                    END_IF;
                  ELSE
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _subfunctionStatus := tempStatusWord;
                    _status := LAcycCom_DriveFunctionStatus#ERR_WRITERECORD;
                    _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                  END_IF;
                  
                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) THEN  // Processing completed without errors                  
                  _fbSubState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_ReadRecord; // WriteRecord completed and continue with ReadRecord
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                END_IF; // #statCmdError = TRUE
                
              LAcycCom_ReadDriveSingleParamStates#FB_BUSY_ReadRecord:  // Reading the values from the drive object
                // Resets ReadRecord command
                IF (_cmdBusy = FALSE) THEN
                  _instReadRecord(request := FALSE,
                                  record := tempRecord);
                END_IF;
                
                _instReadRecord(request := TRUE, // Transfer data record
                                hardwareID := _hwId, // ID number of the hardware component 
                                index := _dataRecordNo, // Data record number
                                maxLength := UINT#0, // Maximum length in bytes of the data record information to be read
                                record := tempRecord, // Destination area for the data record read
                                valid => tempCmdValid, // New data record was received and is valid
                                busy => _cmdBusy, // The reading process is not yet complete
                                error => _cmdError, // An error occurred during the reading process
                                status => tempCmdStatus); // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code

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
                      (tempStatusWord = WORD#16#80C4) THEN // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.
                      
                      IF (_errorCount >= MAX_ERROR_COUNT) THEN
                        _error := TRUE;
                        _stateNumber := _fbSubState;
                        _subfunctionStatus := tempStatusWord;
                        _status := LAcycCom_DriveFunctionStatus#ERR_READRECORD_TEMP_COUNTER;
                        _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                      ELSE
                        _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                        _fbSubStateOld := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_ReadRecord;
                        // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                        IF (tempStatusWord = WORD#16#80A0) THEN
                          _fbSubStateOld := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WriteRecord;
                        END_IF;
                        _fbSubState := LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WAIT;
                      END_IF; // #statErrorCount >= #MAX_ERROR_COUNT
                    ELSE
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _subfunctionStatus := tempStatusWord;
                      _status := LAcycCom_DriveFunctionStatus#ERR_READRECORD;
                      _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                    END_IF;
                    
                    // Error : Reference number of the request does not match with the response reference number 
                  ELSIF (_cmdBusy = FALSE) AND
                    (_refNo <> _respParameterHeader.refNo) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_REFERENCE_NO;
                    _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                    
                    // Error : Invalid response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error)  
                  ELSIF NOT (_reqParameterHeader.reqId = BYTE#16#81 OR _reqParameterHeader.reqId = BYTE#16#01) AND
                    (_cmdBusy = FALSE) AND
                    (tempCmdValid = TRUE) THEN
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_RESPONSE_ID;
                    _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                    
                    // Error : The received number of parameters does not match with the requested number of parameters
                  ELSIF (_cmdBusy = FALSE) AND
                    (TO_INT(_respParameterHeader.parameterNo) <> 1) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER_NO;
                    _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                    
                    // Error : The drive object does not match with the responsed DO
                  ELSIF (_cmdBusy = FALSE) AND
                    (_doId <> _reqParameterHeader.doId) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                    _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                    
                    // No error occurred during reading parameters
                  ELSIF (tempCmdValid = TRUE) THEN
                    // Analyse of the response buffer
                    _parameter[0].format := _respParameterData[0];  // Format of the parameter
                    
                    // Format = Error 
                    IF (((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING)) OR
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                      // V1.5.4 ((TO_SINT(statRespParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (TO_SINT(statRespParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_BYTE)) OR
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE_WO_DATE)) OR // V1.5.4: format "TimeDifference without date indication" added
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE_WO_DATE) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_BYTE)) OR // V1.5.4: format "TimeDifference without date indication" added
                      (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_INTEGER_8))) AND (TO_SINT(_respParameterData[0]) <> LAcycCom_DriveValueFormats#FORMAT_ZERO)
                    THEN
                      
                      // Format = Error, summarize the first and second error byte in a word error variable for each parameter
                      _parameter[0].errorValue := _respParameterData[3];
                      _parameter[0].dwordValue := DWORD#16#0;
                      _parameter[0].realValue := REAL#0.0;
                      diagnostics.errorValue := _parameter[0].errorValue; // V1.3.2
                      
                      IF (_firstParameterError = NO_PARAMETER_ERROR) THEN
                        diagnostics.firstParameterError := 0;
                        _firstParameterError := 0;
                        _error := TRUE;
                        _stateNumber := _fbSubState;
                        _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER;
                        _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
                      END_IF;
                      
                    ELSE
                      CASE TO_SINT(_respParameterData[0]) OF
                        LAcycCom_DriveValueFormats#FORMAT_INTEGER_8:
                          _parameter[0].realValue := TO_REAL(TO_SINT(_respParameterData[2]));
                          _parameter[0].dwordValue := _respParameterData[2];
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics    
                          
                        LAcycCom_DriveValueFormats#FORMAT_INTEGER_16:
                          tempWord.%B0 := _respParameterData[3];
                          tempWord.%B1 := _respParameterData[2];
                          
                          _parameter[0].realValue := TO_REAL(TO_INT(tempWord));
                          _parameter[0].dwordValue := tempWord;
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                          
                        LAcycCom_DriveValueFormats#FORMAT_INTEGER_32:
                          tempDWord.%B0 := _respParameterData[5];
                          tempDWord.%B1 := _respParameterData[4];
                          tempDWord.%B2 := _respParameterData[3];
                          tempDWord.%B3 := _respParameterData[2];
                          
                          _parameter[0].realValue := TO_REAL(TO_DINT(tempDWord));
                          _parameter[0].dwordValue := tempDWord;
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                          
                        LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_8, LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING: // V1.5 change OCTET_STRING:
                          _parameter[0].realValue := TO_REAL(TO_USINT(_respParameterData[2]));
                          _parameter[0].dwordValue := _respParameterData[2];
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics      
                          
                        LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_16:
                          tempWord.%B0 := _respParameterData[3];
                          tempWord.%B1 := _respParameterData[2];
                          
                          _parameter[0].realValue := TO_REAL(TO_UINT(tempWord));
                          _parameter[0].dwordValue := tempWord;
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                          
                        LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_32, LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE, LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE_WO_DATE: // V1.5.4: format "TimeDifference without date indication" added
                          tempDWord.%B0 := _respParameterData[5];
                          tempDWord.%B1 := _respParameterData[4];
                          tempDWord.%B2 := _respParameterData[3];
                          tempDWord.%B3 := _respParameterData[2];
                          
                          _parameter[0].realValue := TO_REAL(TO_UDINT(tempDWord));
                          _parameter[0].dwordValue := tempDWord;
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                          
                        LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT, LAcycCom_DriveValueFormats#FORMAT_DOUBLE_WORD:
                          tempDWord.%B0 := _respParameterData[5];
                          tempDWord.%B1 := _respParameterData[4];
                          tempDWord.%B2 := _respParameterData[3];
                          tempDWord.%B3 := _respParameterData[2];
                          
                          _parameter[0].realValue := TO_REAL(tempDWord);
                          _parameter[0].dwordValue := tempDWord;
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                          
                        LAcycCom_DriveValueFormats#FORMAT_BYTE:
                          _parameter[0].realValue := TO_REAL(TO_DWORD(_respParameterData[2]));
                          _parameter[0].dwordValue := _respParameterData[2];
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics      
                          
                        LAcycCom_DriveValueFormats#FORMAT_WORD:
                          tempWord.%B0 := _respParameterData[3];
                          tempWord.%B1 := _respParameterData[2];
                          
                          _parameter[0].realValue := TO_REAL(TO_DWORD(tempWord));
                          _parameter[0].dwordValue := tempWord;
                          _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                          
                        ELSE
                          ;
                      END_CASE;
                      
                    END_IF; // Format = Error
                    
                    // Copying parameter data into the dataset
                    IF (_warningRetriggering = FALSE) THEN
                      dWordValue := _parameter[0].dwordValue;
                      realValue := _parameter[0].realValue;
                    END_IF;
                    errorValue := _parameter[0].errorValue;
                    
                    _cmdBusy := FALSE;
                    _cmdError := FALSE;
                    
                    // Next state is depending on the FB mode
                    IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                      _status := LAcycCom_DriveFunctionStatus#STATUS_RELEASE;
                      _fbState := LAcycCom_ReadDriveSingleParamStates#FB_RELEASE;
                      
                    ELSIF (_error = FALSE) THEN
                      _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                      _fbState := LAcycCom_ReadDriveSingleParamStates#FB_DONE;
                    END_IF; // #statMode = #MODE_WITH_BUFFER_MANAGER
                  END_IF; // #statCmdError = TRUE
                ELSE
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                END_IF;
                
              LAcycCom_ReadDriveSingleParamStates#FB_BUSY_WAIT:
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
                _status := LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_SUBSTATE;
                _stateNumber := _fbState;
                _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
            END_CASE;
            
          ELSE
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
            _stateNumber := _fbState;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
          END_IF; // ((#buffer.element[#statAllocatedIndex].enable = TRUE) AND (#statMode = #MODE_WITH_BUFFER_MANAGER)) OR #statMode = #MODE_WITHOUT_BUFFER_MANAGER
          
        LAcycCom_ReadDriveSingleParamStates#FB_RELEASE:
          // Check buffer index for correctness
          IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _stateNumber := _fbState;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
            
          ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
            requestBufferHeader.lockBuffer := TRUE;
            IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
              requestBuffer[_allocatedIndex].state.%X2 := TRUE;
            ELSE
              ;
            END_IF;
            requestBufferHeader.lockBuffer := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
            _fbState := LAcycCom_ReadDriveSingleParamStates#FB_DONE;
            
          END_IF;
          
        ELSE
          _error := TRUE;
          _status := LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_STATE;
          _stateNumber := _fbState;
          _fbState := LAcycCom_ReadDriveSingleParamStates#FB_ERROR;
      END_CASE;
      
      // If input execute is set during processing
      IF _warningRetriggering = TRUE AND _error = FALSE THEN
        _status := LAcycCom_DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
      END_IF;
      
    END_IF;
    
    //----------------------------------------------------------------------
    // Error handling and write outputs
    //----------------------------------------------------------------------
    
    // Edge detection
    _executeOld := execute;
    
    IF (_fbState = LAcycCom_ReadDriveSingleParamStates#FB_ERROR) THEN
      // Release the allocated element when error occurs
      IF (_stateNumber <> LAcycCom_ReadDriveSingleParamStates#FB_FIRST_CYCLE) AND (_stateNumber <> LAcycCom_ReadDriveSingleParamStates#FB_ALLOCATE)
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
      
      // FB finished request  
    ELSIF (_fbState = LAcycCom_ReadDriveSingleParamStates#FB_DONE) THEN
      
      // Output for one cycle minimum
      IF (execute = FALSE) AND (_done = TRUE) THEN
        _done := FALSE;
        _status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
        _fbState := LAcycCom_ReadDriveSingleParamStates#FB_IDLE;
      ELSE
        _done := TRUE;
        _busy := FALSE;
      END_IF;
      // If input execute is set during processing
      IF (_warningRetriggering = TRUE) THEN
        _status := LAcycCom_DriveFunctionStatus#ERR_AMBIGUOUS_FB_CALL;
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
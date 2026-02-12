USING System.Timer;
USING Siemens.Simatic.DistributedIO;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_WriteDriveSingleParamStates : SINT (
      FB_IDLE := SINT#0,   // Idle state in FB
      FB_FIRST_CYCLE := SINT#1,   // First cycle state in FB
      FB_ALLOCATE := SINT#2,   // Allocating a request element in request buffer DB
      FB_GET_RESOURCE := SINT#3,   // State to check if the communication to the drive object can be established
      FB_BUSY := SINT#4,   // Busy state in FB
      FB_RELEASE := SINT#5,   // State to return the allocated index
      FB_DONE := SINT#6,   // Done state in FB
      FB_ERROR := SINT#7,   // Error state in FB
      FB_BUSY_WriteRecord_1 := SINT#8,   // WriteRecord (getting format of parameters) in busy state
      FB_BUSY_WriteRecord_2 := SINT#9,   // WriteRecord (changing parameters) in busy state
      FB_BUSY_ReadRecord_1 := SINT#10,   // ReadRecord in busy state
      FB_BUSY_ReadRecord_2 := SINT#11,   // ReadRecord (telegram after writing parameters) in busy state
      FB_BUSY_WAIT := SINT#12   // State when temporary error occurred
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
	/// Functionality: Writes one parameter into a drive object
	///------------------------------------------------------------------------------------------
  FUNCTION_BLOCK LAcycCom_WriteDriveSingleParam
    {S7.Extern = ReadWrite}
    VAR_INPUT
      execute : BOOL;   /// TRUE: Rising edge starts the functionality once
      driveObjectId : INT := -1;   /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
      hardwareId : UINT;   /// Hardware identifier of the hardware module
      parameterNumber : UINT;   /// Number of the parameter
      index : UINT;   /// Parameter index
      writeSelector : LAcycCom_DatatypeSelector; /// type selector to specify the value that will be written to the parameter
      realValue : REAL;   /// Parameter value (real value)
      dWordValue : DWORD;   /// Parameter value (dword value)
      // todo: https://code.siemens.com/axpc/libraries/lacyccom/lib/-/issues/2
      // lrealValue : LREAL;
    END_VAR

    {S7.Extern = ReadOnly}
    VAR_OUTPUT
      done : BOOL;   /// TRUE: Finished writing the parameter
      busy : BOOL;   /// TRUE: FB is not finished and new output values can be expected
      error : BOOL;   /// TRUE: Rising edge informs that an error occurred during the execution of the FB
      status : LAcycCom_DriveFunctionStatus;   /// Status identifier
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
      _doId : BYTE := BYTE#16#00;   /// Intern identification number of the drive object
      _hwId : UINT := UINT#0;   /// Intern hardware identifier of the hardware module
      _refNo : BYTE := BYTE#16#00;   /// Reference number of request
      _status : LAcycCom_DriveFunctionStatus;   /// Static value for output status
      _subfunctionStatus : WORD := WORD#16#0000;   /// Block status or error information
      _withoutResourceManager : BOOL := FALSE;   /// TRUE: No resource manager available; FALSE: Resource manager available
      _fbState : LAcycCom_WriteDriveSingleParamStates;   /// States in the function block state machine
      _fbSubState : LAcycCom_WriteDriveSingleParamStates := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;   /// States in the function block during processing (busy state)
      _fbSubStateOld : LAcycCom_WriteDriveSingleParamStates := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;   /// Previous state when temporary error occurs
      _stateNumber : LAcycCom_WriteDriveSingleParamStates;   /// State of the FB when error occurred
      _errorCount : UINT := UINT#16#0000;   /// Error counter of retry request
      _parameterNumber : UINT := UINT#0;   /// Static value for input parameterNumber
      _parameterIndex : UINT := UINT#0;   /// Static value for input parameterIndex
      _allocatedIndex : INT := 0;   /// Allocated element index in the buffer DB
      _firstParameterError : INT := -1;   /// Number of parameter at which the error occurred (-1: no parameter with error)
      _warningRetriggering : BOOL;   /// TRUE: Input execute is set during processing
      _dataRecordNo : DINT;   /// Used data record
      _parameter : ARRAY[0..WRITE_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameter;   /// Parameter dataset
      _reqParameterHeader : LAcycCom_typeParameterHeader;   /// Request header telegram
      _reqParameterAddress: ARRAY[0..WRITE_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameterAddress;   /// Request address telegram
      _reqParameterInit : LAcycCom_typeParameterAddress := ( attribute := BYTE#16#10, elementNo := BYTE#16#01, parameterNo := UINT#0, index := UINT#0 );   /// Initialisation of the parameter dataset
      _reqWriteParameterHeader : LAcycCom_typeParameterHeader;   /// Request write header telegram
      _reqWriteParameterData : ARRAY[0..LENGTH_WRITE_TELEGRAM_UPPER_LIM] OF BYTE;   /// Request write data telegram
      _respParameterHeader : LAcycCom_typeParameterHeader; // Response header telegram
      _respParameterData : ARRAY[0..LENGTH_READ_TELEGRAM_UPPER_LIM] of BYTE; // Response data telegram;
      _instWriteRecord : WriteRecord;   /// WriteRecord command
      _instReadRecord : ReadRecord;   /// ReadRecord command
      _instOnDelay : OnDelay;   /// OnDelay      
    END_VAR

    VAR_TEMP
      tempCmdValid : BOOL;   // TRUE: New data record was received and is valid
      tempStatusWord : WORD;   // Temporary status
      tempIndex : INT;   // Temporary loop index variable
      tempLastQueueElement : INT;   // Last element in queue
      tempCmdStatus : DWORD;   // Temporary status of WriteRecord and ReadRecord command
      tempUDint : UDINT;   // Temporary udint variable
      tempDWord : DWORD;   // Temporary DWord variable
      tempVoidDiagnostics : LAcycCom_typeDriveDiagnostics;   // Temporary empty diagnostics structure
      tempVoidHeader : LAcycCom_typeParameterHeader;   // Temporary empty header structure
      tempRecord : ARRAY[0..239] OF BYTE;   // Temporary record buffer for WriteRecord and ReadRecord instruction
    END_VAR

    VAR CONSTANT
      NO_PARAMETER_ERROR : INT := -1;   // No parameter error in response telegram
      ALL_ELEMENTS_OCCUPIED : INT := -1;   // All buffer elements are occupied
      FORMAT_ERROR : BYTE := BYTE#16#44;   // Identifier for a format error
      WRITE_PARAMETERS_UPPER_LIM : INT := 0;   // Maximum count of parameters
      LENGTH_WRITE_TELEGRAM_UPPER_LIM : INT := 11;   // Maximum length of parameter information when using WriteRecord
      LENGTH_READ_TELEGRAM_UPPER_LIM : INT := 5;   // Maximum length of telegram for parameter information in Byte
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
      _stateNumber := LAcycCom_WriteDriveSingleParamStates#FB_IDLE;
      _firstParameterError := -1;
      _cmdBusy := FALSE;
      _cmdDone := FALSE;
      _cmdError := FALSE;
      _errorCount := UINT#0;
      _warningRetriggering := FALSE;
      _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;
      _fbState := LAcycCom_WriteDriveSingleParamStates#FB_FIRST_CYCLE;
      
      _instOnDelay(signal := FALSE,
                   duration := TIMER_ALLOCATION);
      
      // FB is currently inactive  
    ELSIF (execute = FALSE) AND (_busy = FALSE) AND
      (_error = TRUE OR _done = TRUE)
    THEN
      IF _error THEN
        // Reset output
        errorValue := BYTE#16#FF;
      END_IF;
      _error := FALSE;
      _busy := FALSE;
      _done := FALSE;
      _fbState := LAcycCom_WriteDriveSingleParamStates#FB_IDLE;
      _status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
      
    END_IF; // tempExecute AND NOT statExecuteOld

    //----------------------------------------------------------------------
    // State Machine
    //----------------------------------------------------------------------

    IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
      CASE _fbState OF
        LAcycCom_WriteDriveSingleParamStates#FB_FIRST_CYCLE:  // First cycle state
          
          // Clearing the sending read buffer
          _reqParameterHeader := tempVoidHeader;
          _reqParameterAddress[0] := _reqParameterInit;
          
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
          
          // Initialization after start, depending on the used PLC data type
          IF driveObjectId < 0 THEN // V1.5
            _dataRecordNo := 16#B02E; // Base Mode Parameter Access local; doId not relevant
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
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
          END_IF;
          
          _hwId := hardwareId;
          _parameterNumber := parameterNumber;
          _parameterIndex := index;
          _parameter[0].realValue := realValue;
          _parameter[0].dwordValue := dWordValue;
          
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
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ALLOCATE;
            
          ELSE
            _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY;
            _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;
          END_IF; // statMode = #MODE_WITH_BUFFER_MANAGER

        LAcycCom_WriteDriveSingleParamStates#FB_ALLOCATE:
          
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
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_GET_RESOURCE;
            
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
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
            
          ELSE
            ; // Waiting until lockbit is reset and a request element is available
          END_IF; // (buffer.lockBuffer = FALSE) AND (buffer.actualWriteIndex >= 0)
          
          _instOnDelay(signal := _timerStart,
                       duration := TIMER_ALLOCATION);
          
          _timerStart := TRUE;
          IF (_instOnDelay.output = TRUE) THEN
            _timerStart := FALSE;
          END_IF;
          
        LAcycCom_WriteDriveSingleParamStates#FB_GET_RESOURCE:
          
          // Check buffer index for correctness
          IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _stateNumber := _fbState;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
            
          ELSE
            IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
              (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
            THEN
              // Request was rejected by buffer manager
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_REQUEST_REJECTED;
              _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
              
            ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
              // Request already released
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_RESOURCE_RELEASED;
              _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
              
            ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
              // Element is enabled
              _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
              _fbState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY;
              _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;
              
            ELSE
              // Element not enabled yet
              // 
              _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            END_IF;
            
          END_IF;
          
        LAcycCom_WriteDriveSingleParamStates#FB_BUSY:
          
          IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE)
            AND (requestBuffer[_allocatedIndex].state.%X3 = FALSE)) OR (_withoutResourceManager = TRUE)
          THEN
            
            CASE _fbSubState OF
              LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1, LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_2:  // Writing the dataset configuration into the drive object
                
                IF (_cmdBusy = FALSE) AND (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1) AND (_error = FALSE) THEN
                  // Resets WriteRecord command
                  _instWriteRecord(request := FALSE,
                                   record := tempRecord);
                 
                  // Creating header data
                  _reqParameterHeader.refNo := _refNo; // Telegram reference number
                  _reqParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                  _reqParameterHeader.doId := _doId;  // Drive object identification number
                  _reqParameterHeader.parameterNo := BYTE#16#01;  // Count of parameters
                  
                  // Copying the dataset into a static variable 
                  _parameter[0].index := UINT#0;
                  _parameter[0].parameterNo := _parameterNumber;
                  // statParameter[0].realValue := statParameterValue; --> V1.5.2: Moved to first cycle
                  _reqParameterAddress[0].parameterNo := _parameter[0].parameterNo;  // Parameter number   
                  _reqParameterAddress[0].index := _parameter[0].index;  // Subindex of parameter
                  
                ELSIF (_cmdBusy = FALSE) AND (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_2) AND (_error = FALSE) THEN
                  // Resets WriteRecord command
                  _instWriteRecord(request := FALSE,
                                   record := tempRecord);
                  
                  // Creating header data
                  _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                  _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                  _reqWriteParameterHeader.doId := _doId;  // Drive object identification number
                  _reqWriteParameterHeader.parameterNo := BYTE#16#01;  // Count of parameters
                  
                  // Creating parameter address - parameter number and parameter index
                  _reqWriteParameterData[0] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                  _reqWriteParameterData[1] := BYTE#16#01; // No. of elements (for single elements=1)        
                  _parameter[0].index := _parameterIndex;
                  _parameter[0].parameterNo := _parameterNumber;
                  
                  // Parameter number                               
                  _reqWriteParameterData[3] := _parameter[0].parameterNo.%B0;
                  _reqWriteParameterData[2] := _parameter[0].parameterNo.%B1;
                  
                  // Subindex of parameter
                  _reqWriteParameterData[5] := _parameter[0].index.%B0;
                  _reqWriteParameterData[4] := _parameter[0].index.%B1;
                  
                  
                  // Creating parameter address - data
                  IF (_parameter[0].format = FORMAT_ERROR) THEN
                    _parameter[0].format := TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT);
                  END_IF;
                  
                  _reqWriteParameterData[6] := _parameter[0].format; // Format of parameter
                  _reqWriteParameterData[7] := BYTE#16#01; // Count of values
                  
                  // copy values from dataset to temporary dword depending on selector
                  IF (writeSelector = LAcycCom_DatatypeSelector#TYPE_REAL) THEN
                    tempDWord := TO_DWORD(_parameter[0].realValue);
                  ELSIF (writeSelector = LAcycCom_DatatypeSelector#TYPE_DWORD) THEN
                    tempDWord := _parameter[0].dwordValue;

                  // todo: https://code.siemens.com/axpc/libraries/lacyccom/lib/-/issues/2
                  // ELSIF (selector = LAcycCom_DatatypeSelector#TYPE_LREAL) THEN
                  END_IF;

                  CASE TO_SINT(_parameter[0].format) OF
                    LAcycCom_DriveValueFormats#FORMAT_INTEGER_8:                     
                      _reqWriteParameterData[9] := tempDWord.%B1;
                      _reqWriteParameterData[8] := tempDWord.%B0;
                      
                    LAcycCom_DriveValueFormats#FORMAT_INTEGER_16:                     
                      _reqWriteParameterData[9] := tempDWord.%B0;
                      _reqWriteParameterData[8] := tempDWord.%B1;
                      
                    LAcycCom_DriveValueFormats#FORMAT_INTEGER_32:                     
                      _reqWriteParameterData[11] := tempDWord.%B0;
                      _reqWriteParameterData[10] := tempDWord.%B1;
                      _reqWriteParameterData[9] := tempDWord.%B2;
                      _reqWriteParameterData[8] := tempDWord.%B3;
                      
                    LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_8, LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING: // V1.5 change OCTET_STRING:                      
                      _reqWriteParameterData[9] := tempDWord.%B1;
                      _reqWriteParameterData[8] := tempDWord.%B0;
                      
                    LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_16:                     
                      _reqWriteParameterData[9] := tempDWord.%B0;
                      _reqWriteParameterData[8] := tempDWord.%B1;
                      
                    LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_32, LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE:                     
                      _reqWriteParameterData[11] := tempDWord.%B0;
                      _reqWriteParameterData[10] := tempDWord.%B1;
                      _reqWriteParameterData[9] := tempDWord.%B2;
                      _reqWriteParameterData[8] := tempDWord.%B3;
                      
                    LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT, LAcycCom_DriveValueFormats#FORMAT_DOUBLE_WORD:                     
                      _reqWriteParameterData[11] := tempDWord.%B0;
                      _reqWriteParameterData[10] := tempDWord.%B1;
                      _reqWriteParameterData[9] := tempDWord.%B2;
                      _reqWriteParameterData[8] := tempDWord.%B3;
                      
                    LAcycCom_DriveValueFormats#FORMAT_BYTE:                     
                      _reqWriteParameterData[9] := tempDWord.%B1;
                      _reqWriteParameterData[8] := tempDWord.%B0;
                      
                    LAcycCom_DriveValueFormats#FORMAT_WORD:                     
                      _reqWriteParameterData[9] := tempDWord.%B0;
                      _reqWriteParameterData[8] := tempDWord.%B1;
                      
                    ELSE
                      ;
                  END_CASE;
                END_IF; // statCmdBusy = FALSE AND statParameterConfig = TRUE
                
                IF (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1) AND (_error = FALSE) THEN
                  SerializeParamAddress(header := _reqParameterHeader, address := _reqParameterAddress, buffer := tempRecord);

                  // WriteRecord command
                  _instWriteRecord(request := TRUE, // Transfer data record
                                   hardwareID := _hwId, // ID number of the hardware component
                                   index := _dataRecordNo, // Data record number
                                   length := UINT#0, // Maximum length of the data record to be transferred in bytes
                                   record := tempRecord, // Data record  
                                   done => _cmdDone, // Data record was transferred 
                                   busy => _cmdBusy, // The writing process is not yet complete
                                   error => _cmdError, // An error occurred during the writing process
                                   status => tempCmdStatus);// Status[1] = Error => Status[2] Error Decode + Status[3] Error Code    
                  
                ELSIF (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_2) AND (_error = FALSE) THEN
                  SerializeParamWrite(header := _reqWriteParameterHeader, data := _reqWriteParameterData, buffer := tempRecord);

                  // WriteRecord command
                  _instWriteRecord(request := TRUE, // Transfer data record
                                   hardwareID := _hwId, // ID number of the hardware component
                                   index := _dataRecordNo, // Data record number
                                   length := UINT#0, // Maximum length of the data record to be transferred in bytes
                                   record := tempRecord, // Data record  
                                   done => _cmdDone, // Data record was transferred 
                                   busy => _cmdBusy, // The writing process is not yet complete
                                   error => _cmdError, // An error occurred during the writing process
                                   status => tempCmdStatus);// Status[1] = Error => Status[2] Error Decode + Status[3] Error Code  
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
                    (tempStatusWord = WORD#16#80C4) THEN // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.
                    
                    IF (_errorCount >= MAX_ERROR_COUNT) THEN
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _subfunctionStatus := tempStatusWord;
                      _status := LAcycCom_DriveFunctionStatus#ERR_WRITERECORD_TEMP_COUNTER;
                      _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                    ELSE
                      _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                      _fbSubStateOld := _fbSubState;
                      _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WAIT;
                    END_IF;
                  ELSE
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _subfunctionStatus := tempStatusWord;
                    _status := LAcycCom_DriveFunctionStatus#ERR_WRITERECORD;
                    _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                  END_IF; // Temporary command status (80A1, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                  
                ELSIF (_cmdBusy = FALSE) AND (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_1; // WriteRecord completed and continue with ReadRecord
                  
                ELSIF (_cmdBusy = FALSE) AND (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_2) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_2; // WriteRecord completed and continue with ReadRecord  
                END_IF; // statCmdError = TRUE
                
              LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_1, LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_2:  // Reading the values from the drive object
                
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
                      (tempStatusWord = WORD#16#80C4) THEN // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.
                      
                      
                      IF (_errorCount >= MAX_ERROR_COUNT) THEN
                        _error := TRUE;
                        _stateNumber := _fbSubState;
                        _subfunctionStatus := tempStatusWord;
                        _status := LAcycCom_DriveFunctionStatus#ERR_READRECORD_TEMP_COUNTER;
                        _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                      ELSE
                        _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                        _fbSubStateOld := _fbSubState;
                        // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                        IF (tempStatusWord = WORD#16#80A0) AND _fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_1 THEN
                          _fbSubStateOld := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;
                        ELSIF (tempStatusWord = WORD#16#80A0) AND _fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_2 THEN
                          _fbSubStateOld := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_2;
                        END_IF;
                        _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WAIT;
                      END_IF;
                    ELSE
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _subfunctionStatus := tempStatusWord;
                      _status := LAcycCom_DriveFunctionStatus#ERR_READRECORD;
                      _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                    END_IF; // Temporary command status (80A0, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 oder 80C4) are valid and retry command
                    
                    // Error : Reference number of the request does not match with the response reference number 
                  ELSIF (_cmdBusy = FALSE) AND
                    (_refNo <> _respParameterHeader.refNo) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_REFERENCE_NO;
                    _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                    
                    // Error : Invalid response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error; 16#02: writing parameter sucessful; 16#82: writing parameter finished with error)  
                  ELSIF (_cmdBusy = FALSE) AND
                    NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01 OR _respParameterHeader.reqId = BYTE#16#02 OR _respParameterHeader.reqId = BYTE#16#82) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_RESPONSE_ID;
                    _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                    
                    // Error : The received number of parameters does not match with the requested number of parameters
                  ELSIF (_cmdBusy = FALSE) AND
                    (TO_INT(_respParameterHeader.parameterNo) <> 1) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER_NO;
                    _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                    
                    // Error : The drive object does not match with the responsed DO
                  ELSIF (_cmdBusy = FALSE) AND
                    (_doId <> _respParameterHeader.doId) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                    _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                    
                    // No error occurred during reading parameters
                  ELSIF (_cmdBusy = FALSE) AND (tempCmdValid = TRUE) AND (_error = FALSE) THEN
                    
                    IF (_fbSubState = LAcycCom_WriteDriveSingleParamStates#FB_BUSY_ReadRecord_1) THEN
                      
                      // Analyse of the response buffer
                      _parameter[0].format := _respParameterData[0];  // Format of the parameter
                      
                      // Format = Error 
                      IF (((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                        ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING)) OR
                        ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                        ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_BYTE)) OR
                        (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_INTEGER_8))) AND (TO_SINT(_respParameterData[0]) <> LAcycCom_DriveValueFormats#FORMAT_ZERO)
                      THEN
                        _parameter[0].errorValue := _respParameterData[3];
                        
                      ELSE
                        _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostic
                        errorValue := _parameter[0].errorValue;
                      END_IF; // Format = Error 
                      
                      _cmdBusy := FALSE;
                      _cmdError := FALSE;
                      _fbState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY;
                      _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_2;
                      
                    ELSE
                      // Error occurred during writing process (changing parameter values) 
                      IF (_respParameterHeader.reqId = BYTE#16#82) THEN  // reqId: 16#82 (Error occurred during writing paramaters)
                        
                        // Parameter error
                        IF (_respParameterData[0] = FORMAT_ERROR) THEN
                          
                          // Save first parameter error in telegram
                          IF (_firstParameterError = NO_PARAMETER_ERROR) THEN
                            _firstParameterError := 0;
                            diagnostics.firstParameterError := _firstParameterError;
                            _error := TRUE;
                            _stateNumber := _fbSubState;
                            _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER;
                            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
                          END_IF;
                          
                          _parameter[0].errorValue := _respParameterData[3];
                          diagnostics.errorValue := _parameter[0].errorValue; // V1.3.2
                          
                          // Parameter without errors  
                        ELSE
                          _parameter[0].errorValue := BYTE#16#FF;
                        END_IF;
                        
                        errorValue := _parameter[0].errorValue;
                      END_IF; // Error occurred during writing process (changing parameter values)

                      _cmdBusy := FALSE;
                      _cmdError := FALSE;
                      _fbSubState := LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WriteRecord_1;

                      // Next state is depending on the FB mode
                      IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                        _status := LAcycCom_DriveFunctionStatus#STATUS_RELEASE;
                        _fbState := LAcycCom_WriteDriveSingleParamStates#FB_RELEASE;
                        
                      ELSIF (_error = FALSE) THEN
                        _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                        _fbState := LAcycCom_WriteDriveSingleParamStates#FB_DONE;
                      END_IF; // statMode = #MODE_WITH_BUFFER_MANAGER
                    END_IF; // statParameterConfig = TRUE
                  END_IF; // statCmdError = TRUE
                ELSE
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                END_IF;

              LAcycCom_WriteDriveSingleParamStates#FB_BUSY_WAIT:
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
                _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
            END_CASE;
            
          ELSE
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
            _stateNumber := _fbState;
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
          END_IF; // ((buffer.element[statAllocatedIndex].enable = TRUE) AND (statMode = #MODE_WITH_BUFFER_MANAGER)) OR statMode = #MODE_WITHOUT_BUFFER_MANAGER
          
        LAcycCom_WriteDriveSingleParamStates#FB_RELEASE:
          // Check buffer index for correctness
          IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _stateNumber := _fbState;
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
            
          ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
            requestBufferHeader.lockBuffer := TRUE;
            IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
              requestBuffer[_allocatedIndex].state.%X2 := TRUE;
            ELSE
              ;
            END_IF;
            requestBufferHeader.lockBuffer := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
            _fbState := LAcycCom_WriteDriveSingleParamStates#FB_DONE;
            
          END_IF;
          
        ELSE
          _error := TRUE;
          _status := LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_STATE;
          _stateNumber := _fbState;
          _fbState := LAcycCom_WriteDriveSingleParamStates#FB_ERROR;
      END_CASE;
      
      // If input execute is set during processing
      IF _warningRetriggering = TRUE AND _error = FALSE THEN
        _status := LAcycCom_DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
      END_IF;
      
    END_IF; // statBusy = TRUE


    //----------------------------------------------------------------------
    // Error handling and write outputs
    //----------------------------------------------------------------------

    // Edge detection
    _executeOld := execute;

    IF (_fbState = LAcycCom_WriteDriveSingleParamStates#FB_ERROR) THEN
      // Release the allocated element when error occurs
      IF (_stateNumber <> LAcycCom_WriteDriveSingleParamStates#FB_FIRST_CYCLE) AND (_stateNumber <> LAcycCom_WriteDriveSingleParamStates#FB_ALLOCATE)
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
    ELSIF (_fbState = LAcycCom_WriteDriveSingleParamStates#FB_DONE) THEN
      
      // Output for one cycle minimum
      IF (execute = FALSE) AND (_done = TRUE) THEN
        _done := FALSE;
        errorValue := BYTE#16#FF;
        _status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
        _fbState := LAcycCom_WriteDriveSingleParamStates#FB_IDLE;
      ELSE
        _done := TRUE;
        _busy := FALSE;
      END_IF;
      // If input execute is set during processing
      IF _warningRetriggering = TRUE THEN
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
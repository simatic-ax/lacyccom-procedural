USING System.Timer;
USING Siemens.Simatic.DistributedIO;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    LAcycCom_typeDriveActDeactStates : SINT (
      FB_IDLE := SINT#0,   // Idle state in FB
      FB_FIRST_CYCLE := SINT#1,   // First cycle state in FB
      FB_ALLOCATE := SINT#2,   // Allocating a buffer element in request buffer DB
      FB_GET_RESOURCE := SINT#3,   // State to check if the communication to the drive object can be established
      FB_BUSY := SINT#4,   // Busy state in FB
      FB_RELEASE := SINT#5,   // State to release the allocated buffer element
      FB_DONE := SINT#6,   // Done state in FB
      FB_ERROR := SINT#7,   // Error state in FB
      FB_BUSY_CONFIG_DO_DATA := SINT#8,   // Configuration of the drive object parameters
      FB_BUSY_WriteRecord_DO_DATA := SINT#9,   // WriteRecord in busy state for writing parameters
      FB_BUSY_ReadRecord_DO_DATA := SINT#10,   // ReadRecord in busy state for writing parameters
      FB_BUSY_CONFIG_READ_DATA := SINT#11,   // Configuration of parameter dataset for reading purpose
      FB_BUSY_CHECK_PROGRESS := SINT#12,   // Processing finished
      FB_BUSY_WriteRecord_READ := SINT#13,   // WriteRecord in busy state for writing the parameter dataset
      FB_BUSY_ReadRecord_READ := SINT#14,   // ReadRecord in busy state for writing the parameter dataset
      FB_BUSY_WAIT := SINT#15   // State when temporary error occurred
    ) := FB_IDLE;
  END_TYPE

  ///------------------------------------------------------------------------------
  /// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Tested with: S7-1513-1 PN
	/// Engineering: SIMATIC AX
	/// Restrictions: ---
	/// Requirements: S7-1200 / S7-1500
	///               FB LAcycCom_ResourceManager is required
	/// Functionality: Activates and de-activates a drive object.
  ///------------------------------------------------------------------------------
  FUNCTION_BLOCK LAcycCom_DriveActDeact
    {S7.Extern = ReadWrite}
    VAR_INPUT
      execute : BOOL;   /// TRUE: Rising edge starts the functionality once
      activateDeactivate : BOOL;   /// TRUE: Activate drive object ; FALSE: Deactivate drive object
      hardwarePresent : BOOL;   /// TRUE: Hardware is present; FALSE: Hardware is not present
      driveObjectId  : INT := -1;   /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
      hardwareId : UINT;   /// Hardware identifier of the hardware module
    END_VAR

    {S7.Extern = ReadOnly}
    VAR_OUTPUT
      done : BOOL;   /// TRUE: Finished activating or deactivating the drive object
      busy : BOOL;   /// TRUE: FB is not finished and new output values can be expected
      error : BOOL;   /// TRUE: Rising edge informs that an error occurred during the execution of the FB
      status : LAcycCom_DriveFunctionStatus := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;   /// Status identifier
      diagnostics : LAcycCom_typeDriveDiagnostics;   /// Diagnostics structure
    END_VAR

    VAR_IN_OUT
      requestBufferHeader : LAcycCom_typeRequestBufferHeader;   /// Interface for header of request buffer
      requestBuffer : ARRAY[*] OF LAcycCom_typeRequestBufferElement;   /// Interface for request buffer
    END_VAR

    VAR
      _busy : BOOL := FALSE;   /// Static value for output busy
      _done : BOOL := FALSE;   /// Static value for output done
      _error : BOOL := FALSE;   /// Static value for output error
      _executeOld : BOOL := FALSE;   /// Old value of execute for edge detection
      _cmdBusy : BOOL := FALSE;   /// TRUE: Process is not yet complete
      _cmdDone : BOOL := FALSE;   /// TRUE: Data record was transferred
      _cmdError : BOOL := FALSE;   /// TRUE: An error occurred during processing
      _timerStart : BOOL := FALSE;   /// TRUE: Starts OnDelay
      _refNo : BYTE := BYTE#16#00;   /// Reference number of request
      _doId : BYTE := BYTE#16#00;   /// Intern identification number of the drive object
      _status : LAcycCom_DriveFunctionStatus := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;   /// Static value for output status
      _subfunctionStatus : WORD := WORD#16#0000;   /// Block status or error information
      _withoutResourceManager : BOOL := FALSE;   /// TRUE: No resource manager available; FALSE: Resource manager available
      _objectMode : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF SINT := [SINT#-1];   /// 0: deactivate drive object; 1: activate drive object; 2: drive object de-activate and not present
      _stateNumber : LAcycCom_typeDriveActDeactStates;   /// State of the FB when error occurred
      _fbState : LAcycCom_typeDriveActDeactStates := LAcycCom_typeDriveActDeactStates#FB_IDLE;   /// State in the function block state machine
      _fbSubState : LAcycCom_typeDriveActDeactStates := LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA;   /// State in the function block during acyclic communication (busy state)
      _fbSubStateOld : LAcycCom_typeDriveActDeactStates := LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA;   /// Previous state when temporary error occurs
      _errorCount : UINT := UINT#0;   /// Error counter of retry request
      _allocatedIndex : INT := 0;   /// Allocated element index in the buffer DB
      _countOfElements : INT := 0;   /// Number of parameters in the dataset
      _firstParameterError : INT := -1;   /// Number of parameter at which the error occurred (-1: no parameter with error)
      _hwId : UINT := UINT#0;   /// Intern hardware identifier of the hardware module
      _warningRetriggering : BOOL;   /// TRUE: Input execute is set during processing
      _dataRecordNo : DINT;   /// Used data record
      _parameter : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] of LAcycCom_typeParameter;   /// Parameter dataset
      _reqWriteParameterHeader : LAcycCom_typeParameterHeader;   /// Request telegram headerto change the parameter values
      _reqWriteParameterData : ARRAY[0..LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;   /// List of parameter (max. 16 parameter)
      _reqReadParameterHeader : LAcycCom_typeParameterHeader;   /// Request telegram header
      _reqReadParameterAddress :  ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameterAddress; // Parameter data in telegram
      _respParameterHeader : LAcycCom_typeParameterHeader;   /// Response telegram header
      _respParameterData : ARRAY[0..LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;   /// List of parameter (max. 16 parameter)
      _reqReadParameterInit : LAcycCom_typeParameterAddress := ( attribute := BYTE#16#10, elementNo := BYTE#16#01, parameterNo := UINT#0, index := UINT#0 );   /// Initialisation of the parameter dataset
      _instWriteRecord  : WriteRecord;   /// WriteRecord command
      _instReadRecord : ReadRecord;   /// ReadRecord command
      _instOnDelay : OnDelay;   /// OnDelay
    END_VAR

    VAR_TEMP
      tempCmdValid : BOOL;   // TRUE: New data record was received and is valid
      tempIndex : INT;   // Temporary loop index variable
      tempLastQueueElement : INT;   // Last element in queue
      tempUDint : UDINT;   // Temporary udint variable
      tempWord : WORD;   // Temporary word variable
      tempStatusWord : WORD;   // Temporary status
      tempDWord : DWORD;   // Temporary DWord variable
      tempCmdStatus : DWORD;   // Temporary status of WriteRecord and ReadRecord command
      tempVoidDiagnostics : LAcycCom_typeDriveDiagnostics;   // Temporary empty diagnostics structure
      tempVoidHeader : LAcycCom_typeParameterHeader;   // Temporary empty header structure
      tempRecord : ARRAY[0..239] OF BYTE;   // Temporary record buffer for WriteRecord and ReadRecord instruction
    END_VAR

    VAR CONSTANT
      CU_DO_ID : BYTE := BYTE#16#01;   // Hardware identifier of the control unit
      DEACTIVATE_MODE : SINT := SINT#0;   // Identifier for deactivation of drive object
      ACTIVATE_MODE : SINT := SINT#1;   // Identifier for activation of drive object
      NOT_PRESENT_MODE : SINT := SINT#2;   // Identifier for no presence of drive object
      MAX_ERROR_COUNT : UINT := UINT#250;   // Maximum error counter
      NO_OF_PARAMETERS_UPPER_LIM : INT := 0;   // Maximum count of parameters
      LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM : INT := 59;   // Maximum length of write telegram in Byte
      LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM : INT := 29;   // Maximum length of read telegram in Byte
      ALL_ELEMENTS_OCCUPIED : INT := -1;   // All buffer elements are occupied
      TIMER_ALLOCATION : TIME := T#10S;   // Timer limit for allocating a buffer element
      TIMER_TEMP_ERROR : TIME := T#200MS;   // Waiting time until next system function block call
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
      _executeOld := execute;

    ELSIF (execute = TRUE) AND (_executeOld = FALSE) THEN
      // First call
      // Initialisation
      _done := FALSE;
      _error := FALSE;
      _countOfElements := 1; // Write 1 parameter
      _status := LAcycCom_DriveFunctionStatus#STATUS_FIRST_CALL;
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
      _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_CONFIG_READ_DATA;
      _fbState := LAcycCom_typeDriveActDeactStates#FB_FIRST_CYCLE;

      _instOnDelay(signal := FALSE,
              duration := TIMER_ALLOCATION);

      // Functionality is busy
      _busy := TRUE;

      // Reset other outputs
      _error := FALSE;
      _status := LAcycCom_DriveFunctionStatus#STATUS_FIRST_CALL;

      busy := _busy;
      error := _error;
      _executeOld := execute;
      RETURN;

    // FB is currently inactive
    ELSIF (execute = FALSE) AND (_busy = FALSE) 
      AND (_error = TRUE OR _done = TRUE)
    THEN
      _error := FALSE;
      _busy := FALSE;
      _done := FALSE;
      _fbState := LAcycCom_typeDriveActDeactStates#FB_IDLE;

      // Write outputs
      status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
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
        LAcycCom_typeDriveActDeactStates#FB_FIRST_CYCLE:  // First cycle state

          // Clearing the sending reading buffer
          _reqReadParameterHeader := tempVoidHeader;
          _reqReadParameterAddress[0] := _reqReadParameterInit;

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
            _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
          END_IF;

          _hwId := hardwareId;
          diagnostics := tempVoidDiagnostics;
          diagnostics.driveObjectId := TO_SINT(_doId);
          diagnostics.hardwareId := _hwId;
          diagnostics.firstParameterError := _firstParameterError; // V1.3.2
          diagnostics.errorValue := BYTE#16#FF; // V1.3.2

          // Set object mode
          IF (activateDeactivate = TRUE) THEN
            // Activate is selected
            _objectMode[0] := ACTIVATE_MODE;
          ELSIF (hardwarePresent = TRUE) THEN
            // Deactivation with hardware present selected
            _objectMode[0] := DEACTIVATE_MODE;
          ELSE
            // Deactivation with hardware not present selected
            _objectMode[0] := NOT_PRESENT_MODE;
          END_IF;

          // Object mode for Control Unit
          IF (activateDeactivate = TRUE) AND (_doId = CU_DO_ID) THEN
            // Activate is selected
            _objectMode[0] := ACTIVATE_MODE;
          ELSIF (activateDeactivate = FALSE) AND (_doId = CU_DO_ID) THEN
            // Deactivation is selected
            _objectMode[0] := DEACTIVATE_MODE;
          END_IF;

          // Next state is depending on the FB mode
          IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
            _status := LAcycCom_DriveFunctionStatus#STATUS_ALLOCATE;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_ALLOCATE;

          ELSIF (_withoutResourceManager = TRUE) AND (_error = FALSE) THEN
            _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_BUSY;
            _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_CONFIG_READ_DATA;

          END_IF;

        LAcycCom_typeDriveActDeactStates#FB_ALLOCATE:

          // Allocation of a buffer element
          IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
            requestBufferHeader.lockBuffer := TRUE;
            _allocatedIndex := requestBufferHeader.nextFreeElement;
            requestBuffer[_allocatedIndex].state := BYTE#16#00;
            requestBuffer[_allocatedIndex].state.%X0 := TRUE;
            requestBuffer[_allocatedIndex].hardwareId := _hwId;
            requestBuffer[_allocatedIndex].queueElementNext := -1;
            _timerStart := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_GET_RESOURCE;

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

              // All Buffer elements are occupied
              IF (tempIndex = requestBufferHeader.bufferUpperBound) THEN
                requestBufferHeader.nextFreeElement := ALL_ELEMENTS_OCCUPIED;
              END_IF;
            END_FOR;

            requestBufferHeader.lockBuffer := FALSE;

          ELSIF (_instOnDelay.output = TRUE) THEN
            _error := TRUE;
            _stateNumber := _fbState;
            _status := LAcycCom_DriveFunctionStatus#ERR_ALLOCATION_TIME;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

          ELSE
            ; // Waiting until lockbit is reset and a buffer element is available
          END_IF; // (#buffer.lockBuffer = FALSE) AND (#buffer.actualWriteIndex >= 0)

          _instOnDelay(signal := _timerStart,
                  duration := TIMER_ALLOCATION);

          _timerStart := TRUE;
          IF (_instOnDelay.output = TRUE) THEN
            _timerStart := FALSE;
          END_IF;

        LAcycCom_typeDriveActDeactStates#FB_GET_RESOURCE:

          // Check buffer index for correctness
          IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _stateNumber := _fbState;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

          ELSE
            IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
              (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
            THEN
              // Request was rejected by buffer manager
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_REQUEST_REJECTED;
              _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

            ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
              // Request already released
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_RESOURCE_RELEASED;
              _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

            ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
              // Element is enabled
              _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
              _fbState := LAcycCom_typeDriveActDeactStates#FB_BUSY;
              _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_CONFIG_READ_DATA;

            ELSE
              // Element not enabled yet
              _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            END_IF;
          END_IF;

        LAcycCom_typeDriveActDeactStates#FB_BUSY:

          IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE)
            AND ((requestBuffer[_allocatedIndex].state.%X3 = FALSE)))
            OR (_withoutResourceManager = TRUE)
          THEN

            CASE _fbSubState OF
              LAcycCom_typeDriveActDeactStates#FB_BUSY_CONFIG_READ_DATA:

                // Creating header data
                _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
                _reqReadParameterHeader.refNo := _refNo; // Telegram reference number
                _reqReadParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                _reqReadParameterHeader.doId := _doId;  // Drive object identification number of CU
                _reqReadParameterHeader.parameterNo := BYTE#16#01;  // Count of parameters
                _countOfElements := NO_OF_PARAMETERS_UPPER_LIM + 1;

                // Copying the dataset into a static variable
                _parameter[0].index := UINT#0;
                _parameter[0].parameterNo := UINT#105; // p105: Activate/De-activate drive object

                _reqReadParameterAddress[0].parameterNo := _parameter[0].parameterNo;  // Parameter number
                _reqReadParameterAddress[0].index := _parameter[0].index;  // Subindex of parameter

                _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                _fbState := LAcycCom_typeDriveActDeactStates#FB_BUSY;
                _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_READ;

              LAcycCom_typeDriveActDeactStates#FB_BUSY_CONFIG_DO_DATA:
                _countOfElements := 0;

                // Changing mode of the complete drive object
                IF _parameter[0].format = TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_INTEGER_16) THEN
                  // Creating header data
                  _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
                  _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                  _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                  _reqWriteParameterHeader.doId := _doId;  // Drive object identification number
                  _reqWriteParameterHeader.parameterNo := BYTE#16#01;  // Count of parameters

                  _reqWriteParameterData[0] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                  _reqWriteParameterData[1] := BYTE#16#01; // No. of elements (for single elements=1)
                  // Parameter number
                  _reqWriteParameterData[3] := _parameter[0].parameterNo.%B0;
                  _reqWriteParameterData[2] := _parameter[0].parameterNo.%B1;
                  // Subindex of parameter
                  _reqWriteParameterData[5] := _parameter[0].index.%B0;
                  _reqWriteParameterData[4] := _parameter[0].index.%B1;
                  _reqWriteParameterData[6] := _parameter[0].format; // Format of parameter
                  _reqWriteParameterData[7] := BYTE#16#01; // Count of values

                  tempDWord := TO_DWORD(_objectMode[0]);
                  _reqWriteParameterData[9] := tempDWord.%B0;
                  _reqWriteParameterData[8] := tempDWord.%B1;

                  _countOfElements := 1;
                  diagnostics.parameterCount := _countOfElements;

                  _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_BUSY;
                  _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA;

                ELSE
                  _status := LAcycCom_DriveFunctionStatus#ERR_DO_MODE;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                END_IF;


              LAcycCom_typeDriveActDeactStates#FB_BUSY_CHECK_PROGRESS:
                // Next state is depending on the FB mode
                IF (_withoutResourceManager = FALSE) THEN
                  _status := LAcycCom_DriveFunctionStatus#STATUS_RELEASE;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_RELEASE;

                ELSE
                  _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_DONE;
                END_IF; // #statMode = #MODE_WITH_BUFFER_MANAGER


              LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_READ, LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA:  // Writing the dataset configuration into the drive object

                IF (_cmdBusy = FALSE) THEN
                  // Resets WriteRecord command
                  _instWriteRecord(request := FALSE,
                      record := tempRecord);

                END_IF; // _cmdBusy = FALSE

                IF (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA) AND (_error = FALSE) THEN
                  SerializeParamWrite(_reqWriteParameterHeader, _reqWriteParameterData, tempRecord);
                  // WriteRecord command
                  _instWriteRecord(request := TRUE,                                                       // Transfer data record
                                    hardwareId := _hwId,                                                 // ID number of the hardware component
                                    index := _dataRecordNo,                                                     // Data record number
                                    length := UINT#0,                                                        // Maximum length of the data record to be transferred in bytes
                                    done => _cmdDone,                                            // Data record was transferred
                                    busy => _cmdBusy,                                            // The writing process is not yet complete
                                    error => _cmdError,                                          // An error occurred during the writing process
                                    status => tempCmdStatus,                                        // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                    record := tempRecord);                               // Data record

                ELSIF (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_READ) AND (_error = FALSE) THEN
                  // WriteRecord command
                  SerializeParamAddress(_reqReadParameterHeader, _reqReadParameterAddress, tempRecord);
                  _instWriteRecord(request := TRUE,                                                       // Transfer data record
                                    hardwareId := _hwId,                                                 // ID number of the hardware component
                                    index := _dataRecordNo,                                                     // Data record number
                                    length := UINT#0,                                                        // Maximum length of the data record to be transferred in bytes
                                    done => _cmdDone,                                            // Data record was transferred
                                    busy => _cmdBusy,                                            // The writing process is not yet complete
                                    error => _cmdError,                                          // An error occurred during the writing process
                                    status => tempCmdStatus,                                        // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                    record := tempRecord);                                // Data record
                END_IF;

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
                      _status := LAcycCom_DriveFunctionStatus#ERR_WriteRecord_TEMP_COUNTER;
                      _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                    ELSE
                      _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                      _fbSubStateOld := _fbSubState; // V1.3.3
                      _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_WAIT;
                    END_IF;

                  ELSE
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _subfunctionStatus := tempStatusWord;
                    _status := LAcycCom_DriveFunctionStatus#ERR_WriteRecord;
                    _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                  END_IF;

                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_DO_DATA; // WriteRecord completed and continue with ReadRecord

                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_READ) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_READ; // WriteRecord completed and continue with ReadRecord
                END_IF; // _cmdError = TRUE

              LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_READ, LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_DO_DATA:  // Reading the values from the drive object
                // Resets ReadRecord command
                IF (_cmdBusy = FALSE) THEN
                  _instReadRecord(request := FALSE,
                      record := tempRecord);
                END_IF;

                _instReadRecord(request := TRUE,              // Transfer data record
                                hardwareID := _hwId,          // ID number of the hardware component
                                index := _dataRecordNo,       // Data record number
                                maxLength := UINT#0,          // Maximum length in bytes of the data record information to be read
                                record := tempRecord,         // New data record was received and is valid
                                valid => tempCmdValid,        // The reading process is not yet complete
                                busy => _cmdBusy,             // An error occurred during the reading process
                                error => _cmdError,           // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                status => tempCmdStatus);     // Destination area for the data record read

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
                      _status := LAcycCom_DriveFunctionStatus#ERR_ReadRecord_TEMP_COUNTER;
                      _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                    ELSE
                      _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                      _fbSubStateOld := _fbSubState;
                      // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                      // V1.5.3 Always start with the WriteRecord command if one of the above listed (temporary) errors occurs
                      // V1.5.3 IF (tempStatusWord = 16#80A0) AND _fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_READ THEN
                      IF _fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_READ THEN // V1.5.3
                        _fbSubStateOld := LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_READ;
                      // V1.5.3 ELSIF (tempStatusWord = 16#80A0) AND _fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_DO_DATA THEN
                      ELSIF _fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_DO_DATA THEN // V1.5.3
                        _fbSubStateOld := LAcycCom_typeDriveActDeactStates#FB_BUSY_WriteRecord_DO_DATA;
                      END_IF;
                      _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_WAIT;
                    END_IF; // _errorCount >= #MAX_ERROR_COUNT

                  ELSE
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _subfunctionStatus := tempStatusWord;
                    _status := LAcycCom_DriveFunctionStatus#ERR_ReadRecord;
                    _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                  END_IF;

                  // Error : Reference number of the request does not match with the response reference number
                ELSIF (_cmdBusy = FALSE) AND
                  (_refNo <> _respParameterHeader.refNo) AND
                  (tempCmdValid = TRUE) THEN

                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_REFERENCE_NO;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                  // Error : Wrong response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error)
                ELSIF NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01 OR _respParameterHeader.reqId = BYTE#16#02 OR _respParameterHeader.reqId = BYTE#16#82) AND
                  (_cmdBusy = FALSE) AND
                  (tempCmdValid = TRUE) THEN
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_RESPONSE_ID;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                  // Error : The received number of parameters does not match with the requested number of parameters
                ELSIF (_cmdBusy = FALSE) AND
                  (TO_INT(_respParameterHeader.parameterNo) <> _countOfElements) AND
                  (tempCmdValid = TRUE)
                THEN

                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER_NO;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                  // Error : The drive object does not match with the responsed DO
                ELSIF (_cmdBusy = FALSE) AND
                  (_respParameterHeader.doId <> _doId) AND
                  (tempCmdValid = TRUE)
                THEN

                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                  // No error occurred during reading parameters
                ELSIF (_cmdBusy = FALSE) AND (tempCmdValid = TRUE) AND (_error = FALSE) THEN
                  // Analyse of the response buffer

                  IF (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_READ) THEN

                    _parameter[0].format := _respParameterData[0];  // Format of the parameter

                    // Format = Error
                    IF (((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING)) OR
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                      ((TO_SINT(_respParameterData[0]) > LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_BYTE)) OR
                      (TO_SINT(_respParameterData[0]) < LAcycCom_DriveValueFormats#FORMAT_INTEGER_8))) AND (TO_SINT(_respParameterData[0]) <> LAcycCom_DriveValueFormats#FORMAT_ZERO)
                    THEN

                      // Format = Error, summarize the first and second error byte in a word error variable for each parameter
                      _parameter[0].errorValue := _respParameterData[3];

                      _firstParameterError := 0;
                      diagnostics.firstParameterError := _firstParameterError;
                      diagnostics.errorValue := _parameter[0].errorValue; // V1.3.2
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER;
                      _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

                      // Check if the drive object ID is invalid
                      // 16#19 Drive object does not exist (access to a drive object that does not exist)
                      IF (_parameter[0].errorValue = BYTE#16#19) THEN
                        _status := LAcycCom_DriveFunctionStatus#ERR_DO_ID;
                      END_IF;


                    ELSE
                      // Analyse of the response buffer
                      tempWord.%B0 := _respParameterData[3];
                      tempWord.%B1 := _respParameterData[2];
                      _parameter[0].realValue := TO_REAL(TO_INT(tempWord));
                      _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics

                      _cmdBusy := FALSE;
                      _cmdError := FALSE;
                      _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                    END_IF; // Format = Error

                  ELSE
                    // Error occurred during writing process (changing parameter values)
                    IF (_respParameterHeader.reqId = BYTE#16#82) THEN  // reqId: 16#82 (Error occurred during writing paramaters)

                      _parameter[0].errorValue := _respParameterData[3];
                      // Save first parameter error in telegram
                      _firstParameterError := 0;
                      diagnostics.firstParameterError := _firstParameterError;
                      diagnostics.errorValue := _parameter[0].errorValue; // V1.3.3
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER;
                      _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                    END_IF; // Error occurred during writing process (changing parameter values)
                  END_IF; // _cmdError = TRUE

                  IF (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_DO_DATA) AND (_error = FALSE) THEN
                    _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_CHECK_PROGRESS; // ReadRecord completed and continue with reading system clock time

                  ELSIF (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_READ) AND (_error = FALSE) THEN
                    _fbSubState := LAcycCom_typeDriveActDeactStates#FB_BUSY_CONFIG_DO_DATA; // ReadRecord completed and continue with writing the RTC time (msec)

                  END_IF; // (_fbSubState = LAcycCom_typeDriveActDeactStates#FB_BUSY_ReadRecord_TIMESTAMP)
                END_IF; // _cmdError = TRUE
              ELSE
                _error := TRUE;
                _stateNumber := _fbSubState;
                _status := LAcycCom_DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
              END_IF;
                
              LAcycCom_typeDriveActDeactStates#FB_BUSY_WAIT:
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
                _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
            END_CASE;

          ELSE
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
            _stateNumber := _fbState;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
          END_IF; // ((#buffer.element[_allocatedIndex].enable = TRUE) AND (#statMode = #MODE_WITH_BUFFER_MANAGER)) OR #statMode = #MODE_WITHOUT_BUFFER_MANAGER

        LAcycCom_typeDriveActDeactStates#FB_RELEASE:
          // Check buffer index for correctness
          IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _stateNumber := _fbState;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;

          ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
            requestBufferHeader.lockBuffer := TRUE;
            IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
              requestBuffer[_allocatedIndex].state.%X2 := TRUE;
            ELSE
              ;
            END_IF;
            requestBufferHeader.lockBuffer := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
            _fbState := LAcycCom_typeDriveActDeactStates#FB_DONE;

          END_IF;

        ELSE
          _error := TRUE;
          _status :=LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_STATE;
          _stateNumber := _fbState;
          _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
      END_CASE;

      // If input execute is set during processing
      IF _warningRetriggering = TRUE AND _error = FALSE THEN
        _status := LAcycCom_DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
      END_IF;

    END_IF;

    //----------------------------------------------------------------------------------------------
    // Write outputs and error handling
    //----------------------------------------------------------------------------------------------

    // Error occurred in request
    IF (_fbState = LAcycCom_typeDriveActDeactStates#FB_ERROR) THEN

      // Release the allocated element when error occurs
      IF (_stateNumber <> LAcycCom_typeDriveActDeactStates#FB_FIRST_CYCLE) AND (_stateNumber <> LAcycCom_typeDriveActDeactStates#FB_ALLOCATE)
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
    ELSIF (_fbState = LAcycCom_typeDriveActDeactStates#FB_DONE) THEN

      // Output for one cycle minimum
      IF (execute = FALSE) AND (_done = TRUE) THEN
        _done := FALSE;
        _status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
        _fbState := LAcycCom_typeDriveActDeactStates#FB_IDLE;

      ELSE
        diagnostics.subfunctionStatus := _subfunctionStatus;
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
    //----------------------------------------------------------------------------------------------
  END_FUNCTION_BLOCK
END_NAMESPACE
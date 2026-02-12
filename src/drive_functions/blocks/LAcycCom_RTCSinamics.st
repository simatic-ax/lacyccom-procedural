USING System.Timer;
USING Siemens.Simatic.DistributedIO;
USING Siemens.Simatic.Hardware.Utilities;
USING Siemens.Simatic.MemoryAccess;
USING Siemens.Simatic.Clocks;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    LAcycCom_RTCSinamicsStates : SINT (
      FB_IDLE := SINT#0,   // Idle state in FB
      FB_FIRST_CYCLE := SINT#1,   // First cycle state in FB
      FB_ALLOCATE := SINT#2,   // Allocating a buffer element in request buffer DB
      FB_GET_RESOURCE := SINT#3,   // State to check if the communication to the drive object can be established
      FB_BUSY := SINT#4,   // Busy state in FB
      FB_RELEASE := SINT#5,   // State to return the allocated index
      FB_DONE := SINT#6,   // Done state in FB
      FB_ERROR := SINT#7,   // Error state in FB
      FB_BUSY_PING_RESET := SINT#8,   // DPWR_DAT in busy state
      FB_BUSY_WriteRecord_TIMESTAMP := SINT#9,   // WriteRecord in busy state for writing the RTC time stamp mode
      FB_BUSY_ReadRecord_TIMESTAMP := SINT#10,   // ReadRecord in busy state for writing the RTC time stamp mode
      FB_BUSY_RD_LOC_T_DAYS := SINT#11,   // Reading the current date of the cpu clock (in days)
      FB_BUSY_RD_LOC_T_MSEC := SINT#12,   // Reading the current time of the cpu clock (in milliseconds)
      FB_BUSY_WriteRecord_TIME_DAYS := SINT#13,   // WriteRecord in busy state for writing the RTC time into SINAMICS (days)
      FB_BUSY_ReadRecord_TIME_DAYS := SINT#14,   // ReadRecord in busy state for writing the RTC time into SINAMICS (days)
      FB_BUSY_WriteRecord_TIME_MSEC := SINT#15,   // WriteRecord in busy state for writing the RTC time into SINAMICS (milliseconds)
      FB_BUSY_ReadRecord_TIME_MSEC := SINT#16,   // ReadRecord in busy state for writing the RTC time into SINAMICS (milliseconds)
      FB_BUSY_WAIT := SINT#17,   // Waiting state
      FB_BUSY_READ_PING := SINT#18,   // Check if time synchronization is successful
      FB_BUSY_WriteRecord_RD_PING := SINT#19,   // WriteRecord in busy state for reading the synchronization status
      FB_BUSY_ReadRecord_RD_PING := SINT#20,   // ReadRecord in busy state for reading the synchronization status
      FB_BUSY_PING_RESET_END := SINT#21,   // Reset ping bit after successful time sync
      FB_BUSY_PING := SINT#22,   // Reading the ping bit in ZSW1
      FB_BUSY_CHECK_PING := SINT#23   // Check if ping is set
    ) := FB_IDLE;
  END_TYPE

  ///------------------------------------------------------------------------------------------
  /// SIEMENS AG
	/// (c)Copyright 2023 All Rights Reserved
	///------------------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Tested with: S7-1513-1 PN
	/// Engineering: SIMATIC AX
	/// Restrictions: Only with 39x telegram
	/// Requirements: S7-1200 / S7-1500
	///               FB LAcycCom_ResourceManager is required
	/// Functionality: LAcycCom_RTCSinamics sets the UTC time in SINAMICS drive system
  ///------------------------------------------------------------------------------------------
  FUNCTION_BLOCK LAcycCom_RTCSinamics
    {S7.Extern = ReadWrite}
    VAR_INPUT
      execute : BOOL;   /// TRUE: Rising edge starts the functionality once
      hwIdTelegram39x : UINT;   /// Hardware identifier of the telegram slot or subslot
    END_VAR

    {S7.Extern = ReadOnly}
    VAR_OUTPUT
      done : BOOL;   /// TRUE: Time synchronization completed successfully
      busy : BOOL;   /// TRUE: FB is not finished and new output values can be expected
      error : BOOL;   /// TRUE: Rising edge informs that an error occurred during the execution of the FB
      status : LAcycCom_DriveFunctionStatus;   /// Status identifier
      rtcRealTimeSyncPING : BOOL;   /// RTC real time synchronization PING // Optional. This bit has to be written in user program (slicing) if user writes complete control word (STW) in application
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
      _pingBit : BOOL := FALSE;   /// TRUE: Ping bit for time synchronization is set
      _refNo : BYTE := BYTE#16#00;   /// Reference number of request
      _status : LAcycCom_DriveFunctionStatus := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;   /// Static value for output status
      _subfunctionStatus : Word := WORD#16#0000;   /// Block status or error information
      _withoutResourceManager : BOOL := FALSE;   /// TRUE: No resource manager available; FALSE: Resource manager available
      _stateNumber : LAcycCom_WriteDriveParamsStates := LAcycCom_WriteDriveParamsStates#FB_IDLE;   /// State of the FB when error occurred
      _fbState : LAcycCom_RTCSinamicsStates := LAcycCom_RTCSinamicsStates#FB_IDLE;   /// States in the function block state machine
      _fbSubState : LAcycCom_RTCSinamicsStates := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP;   /// States in the function block during processing (busy state)
      _fbSubStateOld : LAcycCom_RTCSinamicsStates := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP;   /// Previous state when temporary error occurs
      _errorCount : UINT := UINT#0;   /// Error counter of retry request
      _pingCount : UINT := UINT#0;   /// Counter of the occurred ping
      _allocatedIndex : INT := 0;   /// Allocated element index in the buffer DB
      _firstParameterError : INT := -1;   /// Number of parameter at which the error occurred (-1: no parameter with error)
      _telegramAddress : UINT := UINT#0;   /// Intern telegram address of the hardware module
      _warningRetriggering : BOOL;   /// TRUE: Input execute is set during processing
      _cpuTime : LDATE_AND_TIME;   /// Current data and current time-of-day of the CPU clock
      _pqAddr : INT;   /// Byte offset of the STW 1
      _timestampDay : LINT;
      _timestampMiliseconds : LINT;
      _parameter : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameter;
      _reqParameterHeader : LAcycCom_typeParameterHeader;
      _reqParameterAddress : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF LAcycCom_typeParameterAddress;
      _reqWriteParameterHeader : LAcycCom_typeParameterHeader;
      _reqWriteParameterData : ARRAY[0..LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
      _respParameterHeader : LAcycCom_typeParameterHeader;
      _respParameterData : ARRAY[0..LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
      _instWriteRecord : WriteRecord;   /// WriteRecord command
      _instReadRecord : ReadRecord;   /// ReadRecord command
      _instOnDelay : OnDelay;   /// OnDelay
    END_VAR

    VAR_TEMP
      tempCmdValid : BOOL;   // TRUE: New data record was received and is valid
      tempPointer : INT;   // Temporary pointer variable
      tempIndex : INT;   // Temporary loop index variable
      tempRetValInt : INT;   // Temporary result of a system function as integer
      tempRetValWord : WORD; // Temporary result of a system function as word
      tempLastQueueElement : INT;   // Last element in queue
      tempWord : WORD;   // Temporary word variable
      tempStatusWord : WORD;   // Temporary status
      tempCmdStatus : DWORD;   // Temporary status of WriteRecord and ReadRecord command
      tempUDint : UDINT;   // Temporary udint variable
      tempDWord : DWORD;   // Temporary DWord variable
      tempPQAddr : UDINT;   // Byte offset of the STW 1
      tempPQCount : UINT;   // Length of the used telegram
      tempVoidDiagnostics : LAcycCom_typeDriveDiagnostics;   // Temporary empty diagnostics structure
      tempVoidHeader : LAcycCom_typeParameterHeader;   // Temporary empty header structure
      tempRecord : ARRAY[0..239] OF BYTE;   // Temporary record buffer for WriteRecord and ReadRecord instruction
    END_VAR

    VAR CONSTANT
      MAX_ERROR_COUNT : UINT := UINT#20;   // Maximum error counter
      MAX_PING_COUNT : UINT := UINT#5;   // Maximum ping counter
      NO_PARAMETER_ERROR : INT := -1;   // No parameter error in response telegram
      NO_OF_PARAMETERS_UPPER_LIM : INT := 0;   // Maximum count of parameters
      LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM : INT := 11;   // Maximum length of write telegram in Byte
      LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM : INT := 5;   // Maximum length of read telegram in Byte
      ALL_ELEMENTS_OCCUPIED : INT := -1;   // All buffer elements are occupied
      TIMER_ALLOCATION : TIME := T#10S;   // Timer limit for allocating a buffer element
      TIMER_TEMP_ERROR : TIME := T#100MS;   // Waiting time until next system function block call
      OFFSET_PING_BIT : INT := 1;   // Offset of ping bit in telegram
      BYTE_OFFSET : INT := 1;   // Byte offset for POKE command
      NS_TO_DAYS : LREAL := LREAL#1.0e+9 * 3600 * 24;   // Conversion value from nanoseconds to days
    END_VAR

    // Check if FB is triggered
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
      _status := LAcycCom_DriveFunctionStatus#STATUS_FIRST_CALL;
      _allocatedIndex := 0;
      _telegramAddress := UINT#16#0;
      _subfunctionStatus := WORD#16#0;
      _stateNumber := LAcycCom_WriteDriveParamsStates#FB_IDLE;
      _pingCount := UINT#0;
      _firstParameterError := -1;
      _cmdBusy := FALSE;
      _cmdDone := FALSE;
      _cmdError := FALSE;
      _errorCount := UINT#0;
      _warningRetriggering := FALSE;
      _timestampMiliseconds := LINT#0;
      _timestampDay := LINT#0;
      _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP;
      _fbState := LAcycCom_RTCSinamicsStates#FB_FIRST_CYCLE;
      _error := FALSE;
      _pingBit := FALSE; // Ping bit for time synchronization
      rtcRealTimeSyncPING := FALSE;
      
      //-----------------------------------------------------------------------------------
      // Empty and initialize diagnostics
      _telegramAddress := hwIdTelegram39x;
      diagnostics := tempVoidDiagnostics;
      diagnostics.driveObjectId := SINT#1;
      diagnostics.hardwareId := _telegramAddress;
      diagnostics.parameterCount := 1;
      diagnostics.firstParameterError := _firstParameterError; // V1.3.2
      diagnostics.errorValue := BYTE#16#FF; // V1.3.2
      
      _instOnDelay(signal := FALSE,
            duration := TIMER_ALLOCATION);
      
      tempRetValWord := ReadHardwareIOAddress(hardwareID := _telegramAddress,
                                              outputStartAddress => tempPQAddr,
                                              outputCount => tempPQCount);
      
      IF (tempRetValWord <> WORD#16#0) THEN
        // Address conversion was not successful
        _error := TRUE;
        _stateNumber := _fbState;
        _subfunctionStatus := TO_WORD(tempRetValInt);
        _status := LAcycCom_DriveFunctionStatus#ERR_READ_HARDWARE_IO_ADDRESS;
        _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
        
      ELSE
        _pqAddr := TO_INT(tempPQAddr) + BYTE_OFFSET;
        _busy := TRUE;
        
        // Reset other outputs
        status := LAcycCom_DriveFunctionStatus#STATUS_FIRST_CALL;
        
        busy := _busy;
        error := _error;
      END_IF;
      
      _executeOld := execute;
      
      // FB is currently inactive
    ELSIF (execute = FALSE) AND (_busy = FALSE) AND
      (_error = TRUE OR _done = TRUE)
    THEN
      _error := FALSE;
      _busy := FALSE;
      _done := FALSE;
      _fbState := LAcycCom_RTCSinamicsStates#FB_IDLE;
      
      // Write outputs
      status :=LAcycCom_DriveFunctionStatus# STATUS_NO_CALL;
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
        LAcycCom_RTCSinamicsStates#FB_FIRST_CYCLE:  // First cycle state
          
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
                
          // Initialization after start   
          _parameter[0].errorValue := BYTE#16#FF;
          _parameter[0].format := BYTE#16#0;
          _parameter[0].index := UINT#0;
          _parameter[0].parameterNo := UINT#0;
          _parameter[0].dwordValue := DWORD#0;
          _parameter[0].realValue := REAL#0.0;
    
          // Next state is depending on the FB mode
          IF (_withoutResourceManager = FALSE) THEN
            _status := LAcycCom_DriveFunctionStatus#STATUS_ALLOCATE;
            _fbState := LAcycCom_RTCSinamicsStates#FB_ALLOCATE;
            
          ELSE
            _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
            _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
            _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET;
          END_IF;
          
        LAcycCom_RTCSinamicsStates#FB_ALLOCATE:
          // Allocation of a buffer element
          IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
            requestBufferHeader.lockBuffer := TRUE;
            _allocatedIndex := requestBufferHeader.nextFreeElement;
            requestBuffer[_allocatedIndex].state := BYTE#16#00;
            requestBuffer[_allocatedIndex].state.%X0 := TRUE;
            requestBuffer[_allocatedIndex].hardwareId := _telegramAddress;
            requestBuffer[_allocatedIndex].queueElementNext := -1;
            _timerStart := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            _fbState := LAcycCom_RTCSinamicsStates#FB_GET_RESOURCE;
            
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
            _status := LAcycCom_DriveFunctionStatus#ERR_ALLOCATION_TIME;
            _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
            
          ELSE
            ; // Waiting until lockbit is reset and a buffer element is available
          END_IF; // (buffer.lockBuffer = FALSE) AND (buffer.actualWriteIndex >= 0)
          
          _instOnDelay(signal := _timerStart,
                duration := TIMER_ALLOCATION);
          
          _timerStart := TRUE;
          IF (_instOnDelay.output = TRUE) THEN
            _timerStart := FALSE;
          END_IF;
          
        LAcycCom_RTCSinamicsStates#FB_GET_RESOURCE:
          
          // Check buffer index for correctness
          IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _stateNumber := _fbState;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
            
          ELSE
            IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
              (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
            THEN
              // Job was rejected by buffer manager
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_REQUEST_REJECTED;
              _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
              
            ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
              // Job already released
              _error := TRUE;
              _stateNumber := _fbState;
              _status := LAcycCom_DriveFunctionStatus#ERR_RESOURCE_RELEASED;
              _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
              
            ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
              // Element is enabled
              _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
              _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
              _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET;
              
            ELSE
              // Element not enabled yet
              _status := LAcycCom_DriveFunctionStatus#STATUS_GET_RESOURCE;
            END_IF;
            
          END_IF;
          
        LAcycCom_RTCSinamicsStates#FB_BUSY:
          
          IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE)
            AND (requestBuffer[_allocatedIndex].state.%X3 = FALSE)) OR (_withoutResourceManager = TRUE)
          THEN
            CASE _fbSubState OF
              LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET, LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET_END:  // Reset STW 1 in drive object  
                
                WriteMemory(area := WriteArea#Output, byteOffset := TO_DINT(_pqAddr), bitOffset := OFFSET_PING_BIT, value := FALSE);

                rtcRealTimeSyncPING := FALSE; // Optional. This bit has to be written in user program (slicing) if user writes complete control word (STW) in application
                _pingBit := FALSE; // Ping bit for time synchronization
                
                // Check if error happened before
                IF (_error = FALSE) AND (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET) THEN
                  // Creating header data
                  _refNo := TO_BYTE(TO_UINT(_refNo) + UINT#1);
                  _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                  _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                  _reqWriteParameterHeader.doId := BYTE#1;  // Drive object identification number of CU
                  _reqWriteParameterHeader.parameterNo := BYTE#1;  // Count of parameters
                  
                  // Copying the dataset into a static variable (depending on the used PLC data type)
                  _parameter[0].index := UINT#0;
                  _parameter[0].parameterNo := UINT#3100; // RTC time stamp mode
                  _parameter[0].format := TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_16);
                  _parameter[0].realValue := REAL#1.0;
                  _reqWriteParameterData[0] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                  _reqWriteParameterData[1] := BYTE#16#01; // No. of elements (DEC: for single elements=1) 
                  
                  // Parameter number
                  _reqWriteParameterData[2] := _parameter[0].parameterNo.%B1;
                  _reqWriteParameterData[3] := _parameter[0].parameterNo.%B0;
                  
                  // Subindex of parameter
                  _reqWriteParameterData[4] := _parameter[0].index.%B1;
                  _reqWriteParameterData[5] := _parameter[0].index.%B0;
                  _reqWriteParameterData[6] := _parameter[0].format; // Format of parameter
                  _reqWriteParameterData[7] := BYTE#16#01; // Count of values
                  
                  // Parameter value
                  _reqWriteParameterData[8] := BYTE#16#00;
                  _reqWriteParameterData[9] := BYTE#16#01;
                  
                  _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                  _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP;
                  
                ELSIF (_error = FALSE) THEN
                  // Next state is depending on the FB mode
                  IF (_withoutResourceManager = FALSE) THEN
                    _status := LAcycCom_DriveFunctionStatus#STATUS_RELEASE;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_RELEASE;
                    
                  ELSIF (_withoutResourceManager = TRUE) THEN
                    _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_DONE;
                    
                  END_IF; // statMode = MODE_WITH_BUFFER_MANAGER
                  
                ELSE
                  ; // Error happened
                END_IF;
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_PING:
                tempRetValWord := GetLocalDateTime(_cpuTime); // Reading current date and time of cpu clock
                
                // Error occurred during RD_LOC_T command
                IF (tempRetValWord <> WORD#16#0000) AND (tempRetValWord <> WORD#16#0001) THEN
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _subfunctionStatus := tempRetValWord;
                  _status := LAcycCom_DriveFunctionStatus#ERR_GET_LOCAL_DATE_TIME;
                  _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                  
                ELSE
                  WriteMemory(area := WriteArea#Output, byteOffset := TO_DINT(_pqAddr), bitOffset := OFFSET_PING_BIT, value := TRUE);

                  rtcRealTimeSyncPING := TRUE; // Optional. This bit has to be written in user program (slicing) if user writes complete control word (STW) in application
                  _pingBit := TRUE; // Ping bit for time synchronization
                  
                  _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                  _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_READ_PING;
                END_IF;
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_READ_PING:
                
                // Creating header data
                _refNo := TO_BYTE(TO_UINT(_refNo) + UINT#1);
                _reqParameterHeader.refNo := _refNo; // Telegram reference number
                _reqParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                _reqParameterHeader.doId := BYTE#1;  // Drive object identification number
                _reqParameterHeader.parameterNo := BYTE#16#01;  // Count of parameters
                
                // Copying the dataset into a static variable
                _parameter[0].index := UINT#0;
                _parameter[0].parameterNo := UINT#2090; // p2090: PZD1
                _parameter[0].format := TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_16);
                
                _reqParameterAddress[0].attribute := BYTE#16#10; // Parameter attribut
                _reqParameterAddress[0].elementNo := BYTE#16#1; // Count of elements
                _reqParameterAddress[0].parameterNo := _parameter[0].parameterNo;  // Parameter number    
                _reqParameterAddress[0].index := _parameter[0].index;  // Subindex of parameter
                
                _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
                _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT;
                _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_RD_PING;
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_CHECK_PING:
                
                tempWord := TO_WORD(TO_INT(_parameter[0].realValue)); // STW1 from telegram 39x
                _pingCount := _pingCount + UINT#1; // Count of read attempts from bit 1 in STW1 
                
                IF (tempWord.%X1 = TRUE) THEN  // Bit 1 in STW1 (RTC Real time synchronization PING) is set
                  _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_RD_LOC_T_DAYS;
                  
                ELSIF (_pingCount <= MAX_PING_COUNT) THEN
                  _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                  _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT;
                  _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_READ_PING;
                  
                ELSE
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_PING;
                  _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                END_IF;
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_RD_LOC_T_DAYS:
                
                // Creating header data
                _refNo := TO_BYTE(TO_UINT(_refNo) + UINT#1);
                _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                _reqWriteParameterHeader.doId := BYTE#1;  // Drive object identification number of CU
                _reqWriteParameterHeader.parameterNo := BYTE#1;  // Count of parameters
                
                _timestampDay := TO_LINT(TO_LWORD(_cpuTime)) / TO_LINT(NS_TO_DAYS);

                // Copying the dataset into a static variable (depending on the used PLC data type)
                _parameter[0].index := UINT#1;
                _parameter[0].parameterNo := UINT#3101; // RTC UTC time
                _parameter[0].format := TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_32);
                _parameter[0].realValue := TO_REAL(_timestampDay); // RTC time (days);
                _reqWriteParameterData[0] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                _reqWriteParameterData[1] := BYTE#16#01; // No. of elements (DEC: for single elements=1) 
                
                // Parameter number
                _reqWriteParameterData[2] := _parameter[0].parameterNo.%B1;
                _reqWriteParameterData[3] := _parameter[0].parameterNo.%B0;
                
                // Subindex of parameter
                _reqWriteParameterData[4] := _parameter[0].index.%B1;
                _reqWriteParameterData[5] := _parameter[0].index.%B0;
                _reqWriteParameterData[6] := _parameter[0].format; // Format of parameter
                _reqWriteParameterData[7] := BYTE#16#01; // Count of values
                
                // Parameter value 
                tempDWord := TO_DWORD(_timestampDay); // RTC time (days);
                _reqWriteParameterData[8] := tempDWord.%B3;
                _reqWriteParameterData[9] := tempDWord.%B2;
                _reqWriteParameterData[10] := tempDWord.%B1;
                _reqWriteParameterData[11] := tempDWord.%B0;
                
                _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
                _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT;
                _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_DAYS;
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_RD_LOC_T_MSEC:
                
                // Creating header data
                _refNo := TO_BYTE(TO_UINT(_refNo) + UINT#1);
                _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                _reqWriteParameterHeader.doId := BYTE#1;  // Drive object identification number of CU
                _reqWriteParameterHeader.parameterNo := BYTE#1;  // Count of parameters
                
                _timestampMiliseconds := TO_LINT(TO_LWORD(TO_LTOD(_cpuTime))) / LINT#1000000;

                // Copying the dataset into a static variable (depending on the used PLC data type)
                _parameter[0].index := UINT#0;
                _parameter[0].parameterNo := UINT#3101; // RTC UTC time
                _parameter[0].format := TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_32);

                _parameter[0].realValue := TO_REAL(_timestampMiliseconds); // RTC time (msec)
                _reqWriteParameterData[0] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                _reqWriteParameterData[1] := BYTE#16#01; // No. of elements (DEC: for single elements=1) 
                
                // Parameter number
                _reqWriteParameterData[2] := _parameter[0].parameterNo.%B1;
                _reqWriteParameterData[3] := _parameter[0].parameterNo.%B0;
                
                // Subindex of parameter
                _reqWriteParameterData[4] := _parameter[0].index.%B1;
                _reqWriteParameterData[5] := _parameter[0].index.%B0;
                _reqWriteParameterData[6] := _parameter[0].format; // Format of parameter
                _reqWriteParameterData[7] := BYTE#16#01; // Count of values
                
                // Parameter value
                tempDWord := TO_DWORD(_timestampMiliseconds);
                _reqWriteParameterData[8] := tempDWord.%B3;
                _reqWriteParameterData[9] := tempDWord.%B2;
                _reqWriteParameterData[10] := tempDWord.%B1;
                _reqWriteParameterData[11] := tempDWord.%B0;
                
                _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                _fbState := LAcycCom_RTCSinamicsStates#FB_BUSY;
                _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT;
                _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_MSEC;
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP, LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_DAYS, LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_MSEC, LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_RD_PING:  // Writing the dataset configuration into the drive object
                
                IF (_cmdBusy = FALSE) THEN
                  // Resets WriteRecord command
                  _instWriteRecord(request := FALSE,
                              record := tempRecord);
                  
                END_IF; // statCmdBusy = FALSE
                
                IF (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_RD_PING) AND (_error = FALSE) THEN
                  SerializeParamAddress(header := _reqParameterHeader, address := _reqParameterAddress, buffer := tempRecord);

                  // WriteRecord command
                  _instWriteRecord(request := TRUE,                         // Transfer data record
                              hardwareID := _telegramAddress,       // ID number of the hardware component
                              index := 47,                             // Data record number
                              length := UINT#0,                        // Maximum length of the data record to be transferred in bytes         
                              record := tempRecord,          // Data record 
                              done => _cmdDone,                     // Data record was transferred          
                              busy => _cmdBusy,                     // The writing process is not yet complete
                              error => _cmdError,                   // An error occurred during the writing process
                              status => tempCmdStatus);                // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                ELSE
                  SerializeParamWrite(header := _reqWriteParameterHeader, data := _reqWriteParameterData, buffer := tempRecord);

                  // WriteRecord command
                  _instWriteRecord(request := TRUE,                         // Transfer data record
                              hardwareID := _telegramAddress,       // ID number of the hardware component
                              index := 47,                             // Data record number
                              length := UINT#0,                        // Maximum length of the data record to be transferred in bytes         
                              record := tempRecord,         // Data record  
                              done => _cmdDone,                     // Data record was transferred          
                              busy => _cmdBusy,                     // The writing process is not yet complete
                              error => _cmdError,                   // An error occurred during the writing process
                              status => tempCmdStatus);                // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                END_IF;
                
                
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
                      _status := LAcycCom_DriveFunctionStatus#ERR_WRITERECORD_TEMP_COUNTER;
                      _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                      
                    ELSE
                      _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                      _fbSubStateOld := _fbSubState;
                      _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT;
                    END_IF;
                    
                  ELSE
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _subfunctionStatus := tempStatusWord;
                    _status := LAcycCom_DriveFunctionStatus#ERR_WRITERECORD;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                  END_IF;
                  
                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIMESTAMP; // WriteRecord completed and continue with ReadRecord
                  
                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_DAYS) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_DAYS; // WriteRecord completed and continue with ReadRecord
                  
                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_MSEC) THEN  // Processing completed without errors
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_MSEC; // WriteRecord completed and continue with ReadRecord
                  
                ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_RD_PING) THEN
                  _errorCount := UINT#0;  // V1.5.1 Reset error counter
                  _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_RD_PING; // WriteRecord completed and continue with ReadRecord
                END_IF; // statCmdError = TRUE
                
              LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIMESTAMP, LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_DAYS, LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_MSEC, LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_RD_PING:  // Reading the values from the drive object
                // Resets ReadRecord command
                
                IF (_cmdBusy = FALSE) THEN
                  _instReadRecord(request := FALSE,
                              record := tempRecord);
                END_IF;
                
                _instReadRecord(request := TRUE,                         // Transfer data record
                            hardwareID := _telegramAddress,       // ID number of the hardware component        
                            index := 47,                             // Data record number
                            maxLength := UINT#0,                 // Maximum length in bytes of the data record information to be read
                            record := tempRecord,             // Destination area for the data record read 
                            valid => tempCmdValid,                   // New data record was received and is valid   
                            busy => _cmdBusy,                     // The reading process is not yet complete
                            error => _cmdError,                   // An error occurred during the reading process
                            status => tempCmdStatus);                // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code 
                
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
                        _status := LAcycCom_DriveFunctioNStatus#ERR_READRECORD_TEMP_COUNTER;
                        _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                        
                      ELSE
                        _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                        _fbSubStateOld := _fbSubState;
                        // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                        IF (tempStatusWord = WORD#16#80A0) AND _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIMESTAMP THEN
                          _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP;
                        ELSIF (tempStatusWord = WORD#16#80A0) AND _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_DAYS THEN
                          _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_DAYS;
                        ELSIF (tempStatusWord = WORD#16#80A0) AND _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_MSEC THEN
                          _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_MSEC;
                        ELSIF (tempStatusWord = WORD#16#80A0) AND _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_RD_PING THEN
                          _fbSubStateOld := LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_RD_PING;
                        END_IF;
                        _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT;
                      END_IF; // statErrorCount >= MAX_ERROR_COUNT
                      
                    ELSE
                      _error := TRUE;
                      _stateNumber := _fbSubState;
                      _subfunctionStatus := tempStatusWord;
                      _status := LAcycCom_DriveFunctionStatus#ERR_READRECORD;
                      _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                    END_IF;
                    
                  // Error : Reference number of the request does not match with the response reference number 
                  ELSIF (_cmdBusy = FALSE) AND
                    (_refNo <> _respParameterHeader.refNo) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_REFERENCE_NO;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                    
                    // Error : Wrong response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error)  
                  ELSIF NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01 OR _respParameterHeader.reqId = BYTE#16#02 OR _respParameterHeader.reqId = BYTE#16#82) AND
                    (_cmdBusy = FALSE) AND
                    (tempCmdValid = TRUE) THEN
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_RESPONSE_ID;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                    
                    // Error : The received number of parameters does not match with the requested number of parameters
                  ELSIF (_cmdBusy = FALSE) AND
                    (TO_INT(_respParameterHeader.parameterNo) <> 1) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER_NO;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                    
                    // Error : The drive object does not match with the responsed DO
                  ELSIF (_cmdBusy = FALSE) AND
                    (_respParameterHeader.doId <> BYTE#16#01) AND
                    (tempCmdValid = TRUE) THEN
                    
                    _error := TRUE;
                    _stateNumber := _fbSubState;
                    _status := LAcycCom_DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                    _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                    
                    // No error occurred during reading parameters
                  ELSIF (_cmdBusy = FALSE) AND (tempCmdValid = TRUE) AND (_error = FALSE) THEN
                    // Analyse of the response buffer
                    
                    IF (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_RD_PING) THEN
                      tempPointer := 0;
                      _parameter[0].format := _respParameterData[tempPointer];  // Format of the parameter
                      
                      // Format = Error 
                      IF (((TO_SINT(_respParameterData[tempPointer]) > LAcycCom_DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                        ((TO_SINT(_respParameterData[tempPointer]) > LAcycCom_DriveValueFormats#FORMAT_FLOATING_POINT) AND (TO_SINT(_respParameterData[tempPointer]) < LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING)) OR
                        ((TO_SINT(_respParameterData[tempPointer]) > LAcycCom_DriveValueFormats#FORMAT_OCTET_STRING) AND (TO_SINT(_respParameterData[tempPointer]) < LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                        ((TO_SINT(_respParameterData[tempPointer]) > LAcycCom_DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (TO_SINT(_respParameterData[tempPointer]) < LAcycCom_DriveValueFormats#FORMAT_BYTE)) OR
                        (TO_SINT(_respParameterData[tempPointer]) < LAcycCom_DriveValueFormats#FORMAT_INTEGER_8))) AND (TO_SINT(_respParameterData[tempPointer]) <> LAcycCom_DriveValueFormats#FORMAT_ZERO)
                      THEN
                        
                        // Format = Error, summarize the first and second error byte in a word error variable for each parameter
                        _parameter[0].errorValue := _respParameterData[tempPointer + 3];
                        IF (_firstParameterError = NO_PARAMETER_ERROR) THEN
                          diagnostics.firstParameterError := 0;
                          diagnostics.errorValue := _parameter[0].errorValue; // V1.3.2
                          _firstParameterError := 0;
                          _error := TRUE;
                          _stateNumber := _fbSubState;
                          _status := LAcycCom_DriveFunctionStatus#ERR_PARAMETER;
                          _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
                        END_IF;
                        
                        // Points to the next parameter address
                        tempPointer := tempPointer + 6;
                        
                      ELSE
                        tempWord.%B0 := _respParameterData[tempPointer + 3];
                        tempWord.%B1 := _respParameterData[tempPointer + 2];
                        
                        _parameter[0].realValue := TO_REAL(TO_UINT(tempWord));
                        _parameter[0].errorValue := BYTE#16#FF; // Sets the error status and diagnostics
                        tempPointer := tempPointer + 4; // Points to the next parameter address
                        
                        _cmdBusy := FALSE;
                        _cmdError := FALSE;
                        _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                      END_IF; // Format = Error                 
                      
                    ELSE
                      // Error occurred during writing process (changing parameter values) 
                      IF (_respParameterHeader.reqId = BYTE#16#82) THEN  // reqId: 16#82 (Error occurred during writing paramaters)
                        // Parameter error
                        IF (_respParameterData[0] = TO_BYTE(LAcycCom_DriveValueFormats#FORMAT_ERROR)) THEN
                          _parameter[tempIndex].errorValue := _respParameterData[3];
                          diagnostics.firstParameterError := 0;  // Error in first parameter
                          // Parameter without errors  
                        ELSE
                          _parameter[tempIndex].errorValue := BYTE#16#FF;
                        END_IF;
                      END_IF; // Error occurred during writing process (changing parameter values)
                      
                      _cmdBusy := FALSE;
                      _cmdError := FALSE;
                      _status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
                    END_IF;
                    
                    IF (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIMESTAMP) THEN
                      _errorCount := UINT#0;  // Reset error counter
                      _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_PING; // ReadRecord completed and continue with reading system clock time
                      
                    ELSIF (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_DAYS) THEN
                      _errorCount := UINT#0;  // Reset error counter
                      _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_RD_LOC_T_MSEC; // ReadRecord completed and continue with writing the RTC time (msec)
                      
                    ELSIF (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_MSEC) THEN
                      _errorCount := UINT#0;  // Reset error counter
                      _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET_END;
                      
                    ELSIF (_fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_RD_PING) THEN
                      _errorCount := UINT#0;  // Reset error counter
                      _fbSubState := LAcycCom_RTCSinamicsStates#FB_BUSY_CHECK_PING;
                    END_IF; // (statFBSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIMESTAMP)
                  END_IF; // statCmdError = TRUE
                ELSE
                  _error := TRUE;
                  _stateNumber := _fbSubState;
                  _status := LAcycCom_DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                  _fbState := LAcycCom_typeDriveActDeactStates#FB_ERROR;
                END_IF;

              LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT:
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
                _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
            END_CASE;
          ELSE
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
            _stateNumber := _fbState;
            _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
          END_IF; // ((buffer.element[statAllocatedIndex].enable = TRUE) AND (statMode = MODE_WITH_BUFFER_MANAGER)) OR statMode = MODE_WITHOUT_BUFFER_MANAGER
          
        LAcycCom_RTCSinamicsStates#FB_RELEASE:
          // Check buffer index for correctness
          IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
            _error := TRUE;
            _status := LAcycCom_DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
            _stateNumber := _fbState;
            _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
            
          ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
            requestBufferHeader.lockBuffer := TRUE;
            IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
              requestBuffer[_allocatedIndex].state.%X2 := TRUE;
            ELSE
              ;
            END_IF;

            requestBufferHeader.lockBuffer := FALSE;
            _status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
            _fbState := LAcycCom_RTCSinamicsStates#FB_DONE;
          END_IF;
          
        ELSE
          _error := TRUE;
          _status := LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_STATE;
          _stateNumber := _fbState;
          _fbState := LAcycCom_RTCSinamicsStates#FB_ERROR;
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
    IF (_fbState = LAcycCom_RTCSinamicsStates#FB_ERROR) THEN
      
      // Release the allocation when error occurs
      IF (_stateNumber <> LAcycCom_RTCSinamicsStates#FB_FIRST_CYCLE) AND (_stateNumber <> LAcycCom_RTCSinamicsStates#FB_ALLOCATE)
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
      
      // Reset STW 1 bit 1 in error case, only one time
      IF _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIMESTAMP OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIMESTAMP OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_RD_LOC_T_DAYS OR
        _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_RD_LOC_T_MSEC OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_DAYS OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_DAYS OR
        _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_TIME_MSEC OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_TIME_MSEC OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WAIT OR
        _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_READ_PING OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_WriteRecord_RD_PING OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_ReadRecord_RD_PING OR
        _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_PING_RESET_END OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_PING OR _fbSubState = LAcycCom_RTCSinamicsStates#FB_BUSY_CHECK_PING
      THEN
        // Reset STW 1 bit 1 in drive object  
        WriteMemory(area := WriteArea#Output, byteOffset := TO_DINT(_pqAddr), bitOffset := OFFSET_PING_BIT, value := FALSE);
        rtcRealTimeSyncPING := FALSE; // Optional. This bit has to be written in user program (slicing) if user writes complete control word (STW) in application
        _pingBit := FALSE; // Ping bit for time synchronization
        _fbSubState := LAcycCom_RTCSinamicsStates#FB_IDLE; // Reset
      END_IF;
      
      // Request finished
    ELSIF (_fbState = LAcycCom_RTCSinamicsStates#FB_DONE) THEN
      
      // Output for one cycle minimum
      IF (execute = FALSE) AND (_done = TRUE) THEN
        _done := FALSE;
        _status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
        _fbState := LAcycCom_RTCSinamicsStates#FB_IDLE;
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
    //----------------------------------------------------------------------------------------------
  END_FUNCTION_BLOCK
END_NAMESPACE
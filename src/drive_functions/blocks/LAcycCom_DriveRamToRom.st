USING System.Timer;
USING System.Math;
USING Siemens.Simatic.DistributedIO;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        DriveRamToRomStates : SINT (
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
            /// State of configuration drive object data (read parameter r3996)
            FB_BUSY_READ := SINT#8,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord_READ := SINT#9,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord_READ := SINT#10,
            /// State of configuration drive object data (write parameter p971)
            FB_BUSY_WRITE_PARAM_971 := SINT#11,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord_WRITE_PARAM_971 := SINT#12,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord_WRITE_PARAM_971 := SINT#13,
            /// State of configuration drive object data (write parameter p977)
            FB_BUSY_WRITE_PARAM_977 := SINT#14,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord_WRITE_PARAM_977 := SINT#15,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord_WRITE_PARAM_977 := SINT#16,
            /// Cyclic OnDelay in busy state
            FB_BUSY_CYCLE_TIMER := SINT#17,
            /// State of configuration drive object data (read parameter r3996)
            FB_BUSY_CHECK_PARAM_971 := SINT#18,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord_CHECK_971 := SINT#19,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord_CHECK_971 := SINT#20,
            /// State of configuration drive object data (read parameter p977)
            FB_BUSY_CHECK_PARAM_977 := SINT#21,
            /// WriteRecord in busy state
            FB_BUSY_WriteRecord_CHECK_977 := SINT#22,
            /// ReadRecord in busy state
            FB_BUSY_ReadRecord_CHECK_977 := SINT#23,
            /// Check RAM to ROM progress
            FB_BUSY_CHECK_PROGRESS := SINT#24,
            /// State when temporary error occurred
            FB_BUSY_WAIT := SINT#25
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
    /// Functionality: Copy RAM to ROM of a specific drive object.
    ///==========================================================================================
    FUNCTION_BLOCK DriveRamToRom
        {S7.Extern = ReadWrite}
        VAR_INPUT
            /// TRUE: Rising edge starts the functionality once
            execute : BOOL;
            /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
            driveObjectId : INT := -1;
            /// Hardware identifier of the hardware module
            hardwareId : UINT;
            /// TRUE: Enable saving of all parameters of all drive objects of a multi drive system (e.g. S120). Note: parameter p977 must therefore be available at the addressed drive object. If p977 is not available p971 is written, i.e., the setting also works for single drive systems (e.g. G120)
            enableSavingOfWholeDriveSystem : BOOL;
        END_VAR
    
        {S7.Extern = ReadOnly}
        VAR_OUTPUT
            /// TRUE: RAM data successfully written to ROM
            done : BOOL;
            /// TRUE: FB is not finished and new output values can be expected
            busy : BOOL;
            /// TRUE: Rising edge informs that an error occurred during the execution of the FB
            error : BOOL;
            /// Status identifier
            status : DriveFunctionStatus := DriveFunctionStatus#STATUS_NO_CALL;
            /// Diagnostics structure
            diagnostics : typeDriveDiagnostics;
        END_VAR
    
        VAR_IN_OUT
            /// Interface for header of request buffer
            requestBufferHeader : typeRequestBufferHeader;
            /// Interface for request buffer
            requestBuffer : ARRAY[*] OF typeRequestBufferElement;
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
            /// Intern identification number of the drive object
            _doId : BYTE := BYTE#16#00;
            /// Static value for output status
            _status : DriveFunctionStatus := DriveFunctionStatus#STATUS_NO_CALL;
            /// Block status or error information
            _subfunctionStatus : WORD := WORD#16#0000;
            /// TRUE: No resource manager available; FALSE: Resource manager available
            _withoutResourceManager : BOOL := FALSE;
            /// State of the FB when error occurred
            _stateNumber : SINT := SINT#0;
            /// States in the function block state machine
            _fbState : SINT := DriveRamToRomStates#FB_IDLE;
            /// States in the function block during processing (busy state)
            _fbSubState : SINT := DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971;
            /// Previous state when temporary error occurs
            _fbSubStateOld : SINT := DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971;
            /// Error counter of retry request
            _errorCount : UInt := UINT#0;
            /// Allocated element index in the buffer DB
            _allocatedIndex : INT := 0;
            /// Number of parameters in the dataset
            _countOfElements : INT := 0;
            /// Number of parameter at which the error occurred (-1: no parameter with error)
            _firstParameterError : INT := -1;
            /// Intern hardware identifier of the hardware module
            _hwId : UINT := UINT#0;
            /// TRUE: Input execute is set during processing
            _warningRetriggering : BOOL;
            /// Used data record
            _dataRecordNo : DINT;
            /// TRUE: Starts the OnDelay
            _cyclicTimerStart : BOOL;
            /// Parameter dataset
            _parameter : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF typeParameter;
            /// Parameter dataset for write Ram2Rom
            _parameterRam2Rom : ARRAY[0..0] of typeParameter;
            /// Request telegram to change the parameter values
            _reqWriteParameterHeader : typeParameterHeader;
            /// List of parameter (max. 16 parameter)
            _reqWriteParameterData : ARRAY[0..LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
            /// Request telegram
            _reqReadParameterHeader : typeParameterHeader;
            /// Parameter data in telegram
            _reqReadParameterAddress : ARRAY[0..NO_OF_PARAMETERS_UPPER_LIM] OF typeParameterAddress;
            /// Response telegram
            _respParameterHeader : typeParameterHeader;
            /// List of parameter (max. 16 parameter)
            _respParameterData : ARRAY[0..LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM] OF BYTE;
            /// Initialisation of the parameter dataset
            _reqReadParameterInit : typeParameterAddress := ( attribute := BYTE#16#10, elementNo := BYTE#16#01, parameterNo := UINT#0, index := UINT#0 );
            /// WriteRecord command
            _instWriteRecord  : WriteRecord;
            /// ReadRecord command
            _instReadRecord : ReadRecord;
            /// OnDelay
            _instOnDelay : OnDelay;
        END_VAR
    
        VAR_TEMP
            // TRUE: New data record was received and is valid
            tempCmdValid : BOOL;
            // Temporary loop index variable
            tempIndex : INT;
            // Last element in queue
            tempLastQueueElement : INT;
            // Temporary pointer variable
            tempPointer : INT;
            // Temporary word variable
            tempWord : WORD;
            // Temporary udint variable
            tempUDint : UDINT;
            // Temporary status
            tempStatusWord : WORD;
            // Temporary status of WriteRecord and ReadRecord command
            tempCmdStatus : DWORD;
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
            // Maximum count of parameters
            NO_OF_PARAMETERS_UPPER_LIM : INT := 1;
            // Maximum length of write telegram in Byte
            LENGTH_WRITE_PARAMETER_TELEGRAM_UPPER_LIM : INT := 23;
            // Maximum length of read telegram in Byte
            LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM : INT := 11;
            // All buffer elements are occupied
            ALL_ELEMENTS_OCCUPIED : INT := -1;
            // Timer limit for allocating a buffer element
            TIMER_ALLOCATION : TIME := T#10S;
            // Waiting time until next system function block call
            TIMER_TEMP_ERROR : TIME := T#200MS;
            // Timer interval of checking the result of the Ram to Rom process
            TIMER_CYCLIC : TIME := T#500MS;
            // Maximum drive object number limited by SINAMICS p101
            MAX_DRIVE_OBJECT_NO : INT := 254;
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
            //_status := LAcycCom_DriveFunctionStatus#STATUS_FIRST_CALL;
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
            _countOfElements := 0;
            _warningRetriggering := FALSE;
            _fBSubState := DriveRamToRomStates#FB_BUSY_READ;
            _fBState := DriveRamToRomStates#FB_FIRST_CYCLE;

            // Initialize functionality after triggering FB, e.g. reset of values
            //-----------------------------------------------------------------------------------
            _instOnDelay(signal := FALSE,
                        duration := TIMER_ALLOCATION);

            // Functionality is busy
            _busy := TRUE;

            // Reset other outputs
            _error := FALSE;
            //_status := LAcycCom_DriveFunctionStatus#STATUS_FIRST_CALL;

            busy := _busy;
            error := _error;
            _executeOld := execute;
            RETURN;

        // FB is currently inactive
        ELSIF (execute = FALSE) AND (_busy = FALSE) AND
            (_error = TRUE OR _done = TRUE)
        THEN
            _error := FALSE;
            _busy := FALSE;
            _done := FALSE;
            _fBState := DriveRamToRomStates#FB_IDLE;

            // Write outputs
            _status := DriveFunctionStatus#STATUS_NO_CALL;
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
            RETURN; //Wait for start of functionality
        END_IF;
        //----------------------------------------------------------------------------------------------

        IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
            CASE _fBState OF
                DriveActDeactStates#FB_FIRST_CYCLE:  // First cycle state

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

                    // Initialization after start
                    IF driveObjectId < 0 THEN // V1.5
                        _dataRecordNo := 16#B02E; // Base Mode Parameter Access local; doId not relevant
                        _doId := BYTE#0;

                    ELSIF (driveObjectId <= MAX_DRIVE_OBJECT_NO) AND (driveObjectId <> 0)
                    THEN
                        _dataRecordNo := DINT#16#B02F; // Base Mode Parameter Access global
                        _doId := TO_BYTE(driveObjectId);

                    ELSE // V1.5.2
                        // Wrong drive object ID at input
                        _error := TRUE;
                        _stateNumber := _fBState;
                        _status := DriveFunctionStatus#ERR_INVALID_DRIVE_OBJECT_ID;
                        _fBState := DriveActDeactStates#FB_ERROR;
                    END_IF;

                    _hwId := hardwareId;
                    diagnostics := tempVoidDiagnostics;
                    diagnostics.driveObjectId := TO_SINT(_doId);
                    diagnostics.hardwareId := _hwId;
                    diagnostics.parameterCount := 2;
                    _countOfElements := 2;
                    diagnostics.firstParameterError := _firstParameterError; // V1.3.2
                    diagnostics.errorValue := USINT#16#FF; // V1.3.2

                    _parameter[0].parameterNo := UINT#0;
                    _parameter[1].parameterNo := UINT#0;
                    _parameterRam2Rom[0].parameterNo := UINT#0; // V1.3.3

                    _parameter[0].index := UINT#0;
                    _parameter[1].index := UINT#0;
                    _parameterRam2Rom[0].index := UINT#0;

                    _parameter[0].realValue := REAL#0.0;
                    _parameter[1].realValue := REAL#0.0;
                    _parameterRam2Rom[0].realValue := REAL#0.0;

                    _parameter[0].format := USINT#0;
                    _parameter[1].format := USINT#0;
                    _parameterRam2Rom[0].format := USINT#0;

                    _parameter[0].errorValue := USINT#16#00;
                    _parameter[1].errorValue := USINT#16#00;
                    _parameterRam2Rom[0].errorValue := USINT#16#00;

                    // Next state is depending on the FB mode
                    IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                        _status := DriveFunctionStatus#STATUS_ALLOCATE;
                        _fBState := DriveActDeactStates#FB_ALLOCATE;

                    ELSIF (_withoutResourceManager = TRUE) AND (_error = FALSE) THEN
                        _status := DriveFunctionStatus#STATUS_BUSY;
                        _fBState := DriveActDeactStates#FB_BUSY;
                        _fBSubState := DriveRamToRomStates#FB_BUSY_READ;
                    END_IF;

                DriveActDeactStates#FB_ALLOCATE:
                    // Allocation of a buffer element
                    IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
                        requestBufferHeader.lockBuffer := TRUE;
                        _allocatedIndex := requestBufferHeader.nextFreeElement;
                        requestBuffer[_allocatedIndex].state := BYTE#16#00;
                        requestBuffer[_allocatedIndex].state.%X0 := TRUE;
                        requestBuffer[_allocatedIndex].hardwareId := _hwId;
                        requestBuffer[_allocatedIndex].queueElementNext := -1;
                        _timerStart := FALSE;
                        _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        _fBState := DriveActDeactStates#FB_GET_RESOURCE;

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
                    _stateNumber := _fBState;
                    _status := DriveFunctionStatus#ERR_ALLOCATION_TIME;
                    _fBState := DriveActDeactStates#FB_ERROR;
                ELSE
                    ; // Waiting until lockbit is reset and a buffer element is available
                END_IF; // (#buffer.lockBuffer = FALSE) AND (#buffer.actualWriteIndex >= 0)

                _instOnDelay(signal := _timerStart,
                             duration := TIMER_ALLOCATION);

                _timerStart := TRUE;
                IF (_instOnDelay.output = TRUE) THEN
                    _timerStart := FALSE;
                END_IF;

                DriveActDeactStates#FB_GET_RESOURCE:

                    // Check buffer index for correctness
                    IF (_allocatedIndex < requestBufferHeader.bufferLowerBound) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
                        _error := TRUE;
                        _stateNumber := _fBState;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _fBState := DriveActDeactStates#FB_ERROR;

                    ELSE
                        IF (requestBuffer[_allocatedIndex].state.%X0 = FALSE) OR
                            (requestBuffer[_allocatedIndex].state.%X3 = TRUE)
                        THEN
                            // Request was rejected by buffer manager
                            _error := TRUE;
                            _stateNumber := _fBState;
                            _status := DriveFunctionStatus#ERR_REQUEST_REJECTED;
                            _fBState := DriveActDeactStates#FB_ERROR;

                        ELSIF (requestBuffer[_allocatedIndex].state.%X2 = TRUE) THEN
                            // Request already released
                            _error := TRUE;
                            _stateNumber := _fBState;
                            _status := DriveFunctionStatus#ERR_RESOURCE_RELEASED;
                            _fBState := DriveActDeactStates#FB_ERROR;

                        ELSIF (requestBuffer[_allocatedIndex].state.%X1 = TRUE) THEN
                            // Element is enabled
                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fBState := DriveActDeactStates#FB_BUSY;
                            _fBSubState := DriveRamToRomStates#FB_BUSY_READ;

                        ELSE
                            // Element not enabled yet
                            //
                            _status := DriveFunctionStatus#STATUS_GET_RESOURCE;
                        END_IF;

                    END_IF;

                DriveActDeactStates#FB_BUSY:

                    IF ((requestBuffer[_allocatedIndex].state.%X1 = TRUE) AND (_withoutResourceManager = FALSE) AND ((requestBuffer[_allocatedIndex].state.%X3 = FALSE))) OR
                    (_withoutResourceManager = TRUE)
                    THEN

                    CASE _fBSubState OF

                        DriveRamToRomStates#FB_BUSY_READ:
                            // Creating header data
                            _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
                            _refNo := Max(_refNo, BYTE#16#01);
                            _reqReadParameterHeader.refNo := _refNo; // Telegram reference number
                            _reqReadParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                            _reqReadParameterHeader.doId := _doId;  // Drive object identification number
                            _reqReadParameterHeader.parameterNo := TO_BYTE(_countOfElements);  // Count of parameters

                            // Copying the dataset into a static variable (depending on the used PLC data type)
                            _parameter[0].index := UINT#0;
                            _parameter[0].parameterNo := UINT#971; // Save drive object parameters
                            _parameter[0].format := DriveValueFormats#FORMAT_UNSIGNED_16;
                            _parameter[1].index := UINT#0;
                            _parameter[1].parameterNo := UINT#977; // Save all parameters
                            _parameter[1].format := DriveValueFormats#FORMAT_UNSIGNED_16;


                            _reqReadParameterAddress[0].attribute := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                            _reqReadParameterAddress[0].elementNo := BYTE#16#01; // No. of elements (for single elements=1)

                            _reqReadParameterAddress[1].attribute := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                            _reqReadParameterAddress[1].elementNo := BYTE#16#01; // No. of elements (for single elements=1)

                            // Parameter number
                            _reqReadParameterAddress[0].parameterNo := _parameter[0].parameterNo;
                            _reqReadParameterAddress[1].parameterNo := _parameter[1].parameterNo;

                            // Subindex of parameter
                            _reqReadParameterAddress[0].index := _parameter[0].index;
                            _reqReadParameterAddress[1].index := _parameter[1].index;

                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fBState := DriveActDeactStates#FB_BUSY;
                            _fBSubState := DriveRamToRomStates#FB_BUSY_WriteRecord_READ;

                        DriveRamToRomStates#FB_BUSY_WRITE_PARAM_971, DriveRamToRomStates#FB_BUSY_WRITE_PARAM_977:

                            // Initialize diagnostics and count of elements
                            diagnostics.parameterCount := 1;
                            _countOfElements := 1;

                            // Clearing the receive buffer V1.3.3
                            _respParameterHeader := tempVoidHeader;
                            FOR tempIndex := 0 TO LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM DO
                                _respParameterData[tempIndex] := BYTE#16#00;
                            END_FOR;

                            // Creating header data
                            _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
                            _refNo := Max(_refNo, BYTE#16#01);
                            _reqWriteParameterHeader.refNo := _refNo; // Telegram reference number
                            _reqWriteParameterHeader.reqId := BYTE#16#02;  // 0x02 = change parameters
                            _reqWriteParameterHeader.doId := _doId;  // Drive object identification number of CU
                            _reqWriteParameterHeader.parameterNo := TO_BYTE(_countOfElements);  // Count of parameters

                            // Copying the dataset into a static variable
                            _parameterRam2Rom[0].index := UINT#0;
                            IF (_fBSubState = DriveRamToRomStates#FB_BUSY_WRITE_PARAM_971) THEN // V1.3.3
                                _parameterRam2Rom[0].parameterNo := UINT#971; // Save drive object parameters
                                _fBSubState := DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971;
                            ELSE
                                _parameterRam2Rom[0].parameterNo := UINT#977; // Save all parameters
                                _fBSubState := DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_977;
                            END_IF;

                            _parameterRam2Rom[0].format := DriveValueFormats#FORMAT_UNSIGNED_16;
                            _parameterRam2Rom[0].realValue := REAL#1.0;

                            // Write parameter address
                            _reqWriteParameterData[0] := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                            _reqWriteParameterData[1] := BYTE#16#01; // No. of elements (for single elements=1)

                            // Parameter number
                            _reqWriteParameterData[2] := _parameterRam2Rom[0].parameterNo.%B1;
                            _reqWriteParameterData[3] := _parameterRam2Rom[0].parameterNo.%B0;

                            // Subindex of parameter
                            _reqWriteParameterData[4] := _parameterRam2Rom[0].index.%B1;
                            _reqWriteParameterData[5] := _parameterRam2Rom[0].index.%B0;

                            _reqWriteParameterData[6] := TO_BYTE(_parameterRam2Rom[0].format); // Format of parameter
                            _reqWriteParameterData[7] := BYTE#16#01; // Count of values

                            // Parameter value (= 1.0)
                            _reqWriteParameterData[8] := BYTE#16#00;
                            _reqWriteParameterData[9] := BYTE#16#01;

                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fBState := DriveActDeactStates#FB_BUSY;

                        DriveRamToRomStates#FB_BUSY_CYCLE_TIMER:

                            // Start cyclic timer
                            _instOnDelay(signal := _cyclicTimerStart,
                                         duration := TIMER_CYCLIC);

                            _cyclicTimerStart := TRUE;
                            IF (_instOnDelay.output = TRUE) THEN
                                _cyclicTimerStart := FALSE;
                                _fBSubState := _fBSubStateOld; // V1.3.3
                            END_IF;

                        DriveRamToRomStates#FB_BUSY_CHECK_PARAM_971, DriveRamToRomStates#FB_BUSY_CHECK_PARAM_977:

                            // Clearing the receive buffer V1.3.3
                            _respParameterHeader := tempVoidHeader;
                            FOR tempIndex := 0 TO LENGTH_READ_PARAMETER_TELEGRAM_UPPER_LIM DO
                                _respParameterData[tempIndex] := BYTE#16#00;
                            END_FOR;

                            // Creating header data
                            _refNo := TO_BYTE(TO_SINT(_refNo) + 1);
                            _refNo := Max(_refNo, BYTE#16#01);
                            _reqReadParameterHeader.refNo := _refNo; // Telegram reference number
                            _reqReadParameterHeader.reqId := BYTE#16#01;  // 0x01 = request parameters
                            _reqReadParameterHeader.doId := _doId;  // Drive object identification number of CU
                            _reqReadParameterHeader.parameterNo := TO_BYTE(_countOfElements);  // Count of parameters

                            IF _fBSubState = DriveRamToRomStates#FB_BUSY_CHECK_PARAM_971 THEN // V1.3.3
                                _parameterRam2Rom[0].parameterNo := UINT#971; // Save drive object parameters
                                _fBSubState := DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_971;

                            ELSE
                                _parameterRam2Rom[0].parameterNo := UINT#977; // Save all parameters
                                _fBSubState := DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_977;
                            END_IF;

                            _parameterRam2Rom[0].format := DriveValueFormats#FORMAT_UNSIGNED_16;

                            _status := DriveFunctionStatus#STATUS_BUSY;
                            _fBState := DriveActDeactStates#FB_BUSY;

                            // Copying the dataset into a static variable (depending on the used PLC data type)
                            _parameterRam2Rom[0].index := UINT#0;

                            _reqReadParameterAddress[0].attribute := BYTE#16#10; // Attribute of parameters (0x10=Value, 0x30=Text)
                            _reqReadParameterAddress[0].elementNo := BYTE#16#01; // No. of elements (for single elements=1)

                            // Parameter number
                            _reqReadParameterAddress[0].parameterNo := _parameterRam2Rom[0].parameterNo;

                            // Subindex of parameter
                            _reqReadParameterAddress[0].index := _parameterRam2Rom[0].index;

                        DriveRamToRomStates#FB_BUSY_CHECK_PROGRESS:

                            IF (_parameterRam2Rom[0].realValue = REAL#0.0) // Ram2Rom is completed
                            THEN

                                // Next state is depending on the FB mode
                                IF (_withoutResourceManager = FALSE) AND (_error = FALSE) THEN
                                _status := DriveFunctionStatus#STATUS_RELEASE;
                                _fBState := DriveActDeactStates#FB_RELEASE;

                                ELSIF (_withoutResourceManager = TRUE) AND (_error = FALSE) THEN
                                _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                                _fBState := DriveActDeactStates#FB_DONE;
                                END_IF; // _mode = #MODE_WITH_BUFFER_MANAGER

                            ELSE
                                _status := DriveFunctionStatus#STATUS_BUSY;
                                _fBSubState := DriveRamToRomStates#FB_BUSY_CYCLE_TIMER;
                            END_IF;

                        // Writing the dataset configuration into the drive object
                        DriveRamToRomStates#FB_BUSY_WriteRecord_READ, DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971, DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_977, DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_971, DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_977:

                            IF (_cmdBusy = FALSE) THEN
                                // Resets WriteRecord command
                                _instWriteRecord(request := FALSE,
                                                 record := tempRecord);

                            END_IF; // _cmdBusy = FALSE

                            IF ((_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971) OR (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_977)) AND (_error = FALSE) THEN
                                SerializeParamWrite(_reqWriteParameterHeader, _reqWriteParameterData, tempRecord);
                                // WriteRecord command
                                _instWriteRecord(request := TRUE,                     // Transfer data record
                                                 hardwareId := _hwId,                 // ID number of the hardware component
                                                 index := _dataRecordNo,              // Data record number
                                                 length := UINT#0,                    // Maximum length of the data record to be transferred in bytes
                                                 done => _cmdDone,                    // Data record was transferred
                                                 busy => _cmdBusy,                    // The writing process is not yet complete
                                                 error => _cmdError,                  // An error occurred during the writing process
                                                 status => tempCmdStatus,             // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                                 record := tempRecord);               // Data record

                            ELSIF ((_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_971) OR (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_READ) OR (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_977))
                                AND (_error = FALSE)
                            THEN
                                SerializeParamAddress(_reqReadParameterHeader, _reqReadParameterAddress, tempRecord);
                                // WriteRecord command
                                _instWriteRecord(request := TRUE,                     // Transfer data record
                                                 hardwareId := _hwId,                 // ID number of the hardware component
                                                 index := _dataRecordNo,              // Data record number
                                                 length := UINT#0,                    // Maximum length of the data record to be transferred in bytes
                                                 done => _cmdDone,                    // Data record was transferred
                                                 busy => _cmdBusy,                    // The writing process is not yet complete
                                                 error => _cmdError,                  // An error occurred during the writing process
                                                 status => tempCmdStatus,             // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                                 record := tempRecord);               // Data record
                            END_IF;

                            // Error occurred
                            IF (_cmdError = TRUE) AND (_error = FALSE) THEN
                                tempStatusWord.%B0 := tempCmdStatus.%B1;
                                tempStatusWord.%B1 := tempCmdStatus.%B2;

                                // Temporary command status (80A1, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 or 80C4) are valid and retry command
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
                                        _stateNumber := _fBSubState;
                                        _subfunctionStatus := tempStatusWord;
                                        _status := DriveFunctionStatus#ERR_WRITERECORD_TEMP_COUNTER;
                                        _fBState := DriveActDeactStates#FB_ERROR;

                                    ELSE
                                        _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                        _fBSubStateOld := _fBSubState; // // V1.3.3
                                        _fBSubState := DriveRamToRomStates#FB_BUSY_WAIT;
                                    END_IF;

                                ELSIF (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_971) OR (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_977) THEN // V1.3.3
                                    _error := TRUE;
                                    _stateNumber := _fBSubState;
                                    _subfunctionStatus := tempStatusWord;
                                    _status := DriveFunctionStatus#ERR_MISSING_CONFIRMATION;
                                    _fBState := DriveActDeactStates#FB_ERROR;

                                ELSE
                                    _error := TRUE;
                                    _stateNumber := _fBSubState;
                                    _subfunctionStatus := tempStatusWord;
                                    _status := DriveFunctionStatus#ERR_WRITERECORD;
                                    _fBState := DriveActDeactStates#FB_ERROR;
                                END_IF;

                            ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_READ) THEN  // Processing completed without errors
                                _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                _fBSubState := DriveRamToRomStates#FB_BUSY_ReadRecord_READ; // WriteRecord completed and continue with ReadRecord

                            ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971) THEN  // Processing completed without errors
                                _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                _fBSubState := DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_971; // WriteRecord completed and continue with ReadRecord

                            ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_971) THEN  // Processing completed without errors
                                _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                _fBSubState := DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_971; // WriteRecord completed and continue with ReadRecord

                            ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_977) THEN  // Processing completed without errors
                                _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                _fBSubState := DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_977; // WriteRecord completed and continue with ReadRecord

                            ELSIF (_cmdDone = TRUE) AND (_error = FALSE) AND (_fBSubState = DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_977) THEN  // Processing completed without errors
                                _errorCount := UINT#0;  // V1.5.1 Reset error counter
                                _fBSubState := DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_977; // WriteRecord completed and continue with ReadRecord
                                
                            END_IF; // _cmdError = TRUE

                        // Reading the values from the drive object
                        DriveRamToRomStates#FB_BUSY_ReadRecord_READ, DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_971, DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_977, DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_971, DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_977:
                            // Resets ReadRecord command
                            IF (_cmdBusy = FALSE) THEN
                                _instReadRecord(request := FALSE,
                                                record := tempRecord);
                            END_IF;

                            _instReadRecord(request := TRUE,                     // Transfer data record
                                            hardwareID := _hwId,                 // ID number of the hardware component
                                            index := _dataRecordNo,              // Data record number
                                            maxLength := UINT#0,                 // Maximum length in bytes of the data record information to be read
                                            record := tempRecord,                // New data record was received and is valid
                                            valid => tempCmdValid,               // The reading process is not yet complete
                                            busy => _cmdBusy,                    // An error occurred during the reading process
                                            error => _cmdError,                  // Status[1] = Error => Status[2] Error Decode + Status[3] Error Code
                                            status => tempCmdStatus);            // Destination area for the data record read

                            tempUDint := DeserializeParamResponse(header => _respParameterHeader, response => _respParameterData, buffer := tempRecord);

                            IF tempUDint > UDINT#0 THEN
                                // Error occurred
                                IF (_cmdError = TRUE) THEN
                                    // Get the error information from the status information
                                    tempStatusWord.%B0 := tempCmdStatus.%B1;
                                    tempStatusWord.%B1 := tempCmdStatus.%B2;

                                    // Temporary command status (80A0, 80A7, 80B5, 80C0, 80C1, 80C2, 80C3 or 80C4) are valid and retry command
                                    IF (tempStatusWord = WORD#16#80A0) OR  // Negative acknowledgment when reading the module
                                        (tempStatusWord = WORD#16#80A7) OR     // DP slave or module is occupied (temporary error)
                                        (tempStatusWord = WORD#16#80B5) OR     // DP slave or module not ready
                                        (tempStatusWord = WORD#16#80C0) OR     // The data can only be written when the CPU is in STOP mode. Note: this means that writing by the user program is not possible. You can only write the data online with PG/PC.
                                        (tempStatusWord = WORD#16#80C1) OR     // The data of the previous write job on the module for the same data record have not yet been processed by the module.
                                        (tempStatusWord = WORD#16#80C2) OR     // The module is currently processing the maximum possible number of jobs for a CPU.
                                        (tempStatusWord = WORD#16#80C3) OR     // The required operating resources are currently occupied.
                                        (tempStatusWord = WORD#16#80C4)
                                    THEN   // Internal temporary error. Job could not be executed. Repeat the job. If this error occurs often, check your installation for sources of electrical interference.

                                        IF (_errorCount >= MAX_ERROR_COUNT) THEN
                                            _error := TRUE;
                                            _stateNumber := _fBSubState;
                                            _subfunctionStatus := tempStatusWord;
                                            _status := DriveFunctionStatus#ERR_READRECORD_TEMP_COUNTER;
                                            _fBState := DriveActDeactStates#FB_ERROR;

                                        ELSE
                                            _errorCount := _errorCount + UINT#1;  // Increment internal error counter
                                            _fBSubStateOld := _fBSubState;
                                            // V1.3.2. If error 80A0 then should be retry with WriteRecord command
                                            IF (tempStatusWord = WORD#16#80A0) AND _fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_971 THEN
                                                _fBSubStateOld := DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_971;
                                            ELSIF (tempStatusWord = WORD#16#80A0) AND _fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_971 THEN
                                                _fBSubStateOld := DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_971;
                                            ELSIF (tempStatusWord = WORD#16#80A0) AND _fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_READ THEN
                                                _fBSubStateOld := DriveRamToRomStates#FB_BUSY_WriteRecord_READ;
                                            ELSIF (tempStatusWord = WORD#16#80A0) AND _fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_977 THEN
                                                _fBSubStateOld := DriveRamToRomStates#FB_BUSY_WriteRecord_CHECK_977;
                                            ELSIF (tempStatusWord = WORD#16#80A0) AND _fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_977 THEN
                                                _fBSubStateOld := DriveRamToRomStates#FB_BUSY_WriteRecord_WRITE_PARAM_977;
                                            END_IF;
                                                _fBSubState := DriveRamToRomStates#FB_BUSY_WAIT;
                                        END_IF; // _errorCount >= #MAX_ERROR_COUNT

                                    ELSIF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_971) OR (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_977) THEN // V1.3.3
                                        _error := TRUE;
                                        _stateNumber := _fBSubState;
                                        _subfunctionStatus := tempStatusWord;
                                        _status := DriveFunctionStatus#ERR_MISSING_CONFIRMATION;
                                        _fBState := DriveActDeactStates#FB_ERROR;
                                    ELSE
                                        _error := TRUE;
                                        _stateNumber := _fBSubState;
                                        _subfunctionStatus := tempStatusWord;
                                        _status := DriveFunctionStatus#ERR_READRECORD;
                                        _fBState := DriveActDeactStates#FB_ERROR;
                                    END_IF;

                                // Error : Reference number of the request does not match with the response reference number
                                ELSIF (_cmdBusy = FALSE) AND
                                    (_refNo <> _respParameterHeader.refNo) AND
                                    (tempCmdValid = TRUE) THEN

                                    _error := TRUE;
                                    _stateNumber := _fBSubState;
                                    _status := DriveFunctionStatus#ERR_REFERENCE_NO;
                                    _fBState := DriveActDeactStates#FB_ERROR;

                                // Error : Wrong response from the drive object (reqId: 16#01 - reading parameter successful; 16#81: reading parameter finished with error)
                                ELSIF NOT (_respParameterHeader.reqId = BYTE#16#81 OR _respParameterHeader.reqId = BYTE#16#01 OR _respParameterHeader.reqId = BYTE#16#02 OR _respParameterHeader.reqId = BYTE#16#82) AND
                                    (_cmdBusy = FALSE) AND
                                    (tempCmdValid = TRUE) THEN
                                    _error := TRUE;
                                    _stateNumber := _fBSubState;
                                    _status := DriveFunctionStatus#ERR_RESPONSE_ID;
                                    _fBState := DriveActDeactStates#FB_ERROR;

                                // Error : The received number of parameters does not match with the requested number of parameters
                                ELSIF (_cmdBusy = FALSE) AND
                                    (TO_INT(_respParameterHeader.parameterNo) <> _countOfElements) AND
                                    (tempCmdValid = TRUE) THEN

                                    _error := TRUE;
                                    _stateNumber := _fBSubState;
                                    _status := DriveFunctionStatus#ERR_PARAMETER_NO;
                                    _fBState := DriveActDeactStates#FB_ERROR;

                                // Error : The drive object does not match with the responsed DO
                                ELSIF (_cmdBusy = FALSE) AND
                                    (_respParameterHeader.doId <> _doId) AND
                                    (tempCmdValid = TRUE) THEN

                                    _error := TRUE;
                                    _stateNumber := _fBSubState;
                                    _status := DriveFunctionStatus#ERR_DRIVE_OBJECT_NO;
                                    _fBState := DriveActDeactStates#FB_ERROR;

                                // No error occurred during reading parameters
                                ELSIF (_cmdBusy = FALSE) AND (tempCmdValid = TRUE) AND (_error = FALSE) THEN
                                    // Analyse of the response buffer

                                    IF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_READ) THEN // V1.3.3
                                        // If p971 is available then write p971
                                        // otherwise write p977 (e.g. drive S210)

                                        // Analyse of the response buffer
                                        tempPointer := 0;
                                        FOR tempIndex := 0 TO NO_OF_PARAMETERS_UPPER_LIM DO
                                            _parameter[tempIndex].format := TO_USINT(_respParameterData[tempPointer]);  // Format of the parameter
                                            // Format = Error
                                            IF (((_parameter[tempIndex].format > DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_FLOATING_POINT) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_OCTET_STRING)) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_OCTET_STRING) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                                                ((_parameter[tempIndex].format > DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (_parameter[tempIndex].format < DriveValueFormats#FORMAT_BYTE)) OR
                                                (_parameter[tempIndex].format < DriveValueFormats#FORMAT_INTEGER_8))) AND (_parameter[tempIndex].format <> DriveValueFormats#FORMAT_ZERO)
                                            THEN
                                                // Format = Error, summarize the first and second error byte in a WORD error variable for each parameter
                                                _parameter[tempIndex].errorValue := TO_USINT(_respParameterData[tempPointer + 3]);

                                                // Points to the next parameter address
                                                tempPointer := tempPointer + 6;
                                            ELSE
                                                CASE _parameter[tempIndex].format OF
                                                    DriveValueFormats#FORMAT_UNSIGNED_16:
                                                        tempWord.%B0 := _respParameterData[tempPointer + 3];
                                                        tempWord.%B1 := _respParameterData[tempPointer + 2];

                                                        _parameter[tempIndex].realValue := TO_REAL(TO_UINT(tempWord));
                                                        _parameter[tempIndex].errorValue := USINT#16#FF; // Sets the error status and diagnostics
                                                        tempPointer := tempPointer + 4; // Points to the next parameter address

                                                    ELSE
                                                        // Wrong format. _parameter[n].format <> LAcycCom_DriveValueFormats#FORMAT_UNSIGNED_16
                                                        _firstParameterError := tempIndex;
                                                        diagnostics.firstParameterError := _firstParameterError;
                                                        _status := DriveFunctionStatus#ERR_PARAMETER;
                                                        _error := TRUE;
                                                        _stateNumber := _fBSubState;
                                                        _fBState := DriveActDeactStates#FB_ERROR;
                                                    EXIT;
                                                END_CASE;
                                            END_IF;
                                        END_FOR;

                                    IF (enableSavingOfWholeDriveSystem = FALSE) THEN // V1.5.3 "old" logic (save parameters of a specific DO) is active, i.e., if p971 is available, p971 is written, otherwise p977 is written if available (e.g. for drive S210)
                                        IF (_parameter[0].errorValue = USINT#16#FF) AND (_error = FALSE) THEN
                                            // Write p971
                                            _cmdBusy := FALSE;
                                            _cmdError := FALSE;
                                            _status := DriveFunctionStatus#STATUS_BUSY;
                                            _fBState := DriveActDeactStates#FB_BUSY;
                                            _fBSubState := DriveRamToRomStates#FB_BUSY_WRITE_PARAM_971;
                                        ELSIF (_parameter[1].errorValue = USINT#16#FF)
                                            AND (_error = FALSE)
                                        THEN
                                            // Write p977
                                            _cmdBusy := FALSE;
                                            _cmdError := FALSE;
                                            _status := DriveFunctionStatus#STATUS_BUSY;
                                            _fBState := DriveActDeactStates#FB_BUSY;
                                            _fBSubState := DriveRamToRomStates#FB_BUSY_WRITE_PARAM_977;
                                        ELSIF (_parameter[0].errorValue = DriveValueErrors#DRIVE_OBJECT_DOES_NOT_EXIST) AND (_parameter[1].errorValue = DriveValueErrors#DRIVE_OBJECT_DOES_NOT_EXIST)
                                            AND (_error = FALSE)
                                        THEN
                                            // 16#19 Drive object does not exist (access to a drive object that does not exist)
                                            _firstParameterError := 0;
                                            diagnostics.firstParameterError := _firstParameterError;
                                            diagnostics.errorValue := _parameter[0].errorValue;
                                            _status := DriveFunctionStatus#ERR_DO_ID;
                                            _error := TRUE;
                                            _stateNumber := _fBSubState;
                                            _fBState := DriveActDeactStates#FB_ERROR;

                                        ELSIF (_error = FALSE) THEN
                                            // Both parameter are unavailable
                                            _firstParameterError := 0;
                                            diagnostics.firstParameterError := _firstParameterError;
                                            diagnostics.errorValue := _parameter[0].errorValue;
                                            _status := DriveFunctionStatus#ERR_PARAMETER;
                                            _error := TRUE;
                                            _stateNumber := _fBSubState;
                                            _fBState := DriveActDeactStates#FB_ERROR;
                                        END_IF;

                                    ELSE // (enableSavingOfWholeDriveSystem = TRUE) V1.5.3 "new" logic to enable saving the parameters of the whole drive system is active, i.e., if p977 is available, p977 is written, otherwise p971 is written if available (e.g. for drive G120)
                                        IF (_parameter[1].errorValue = USINT#16#FF)
                                            AND (_error = FALSE)
                                        THEN
                                            // Write p977
                                            _cmdBusy := FALSE;
                                            _cmdError := FALSE;
                                            _status := DriveFunctionStatus#STATUS_BUSY;
                                            _fBState := DriveActDeactStates#FB_BUSY;
                                            _fBSubState := DriveRamToRomStates#FB_BUSY_WRITE_PARAM_977;
                                        ELSIF (_parameter[0].errorValue = USINT#16#FF) AND (_error = FALSE) THEN
                                            // Write p971
                                            _cmdBusy := FALSE;
                                            _cmdError := FALSE;
                                            _status := DriveFunctionStatus#STATUS_BUSY;
                                            _fBState := DriveActDeactStates#FB_BUSY;
                                            _fBSubState := DriveRamToRomStates#FB_BUSY_WRITE_PARAM_971;
                                        ELSIF (_parameter[0].errorValue = DriveValueErrors#DRIVE_OBJECT_DOES_NOT_EXIST) AND (_parameter[1].errorValue = DriveValueErrors#DRIVE_OBJECT_DOES_NOT_EXIST)
                                            AND (_error = FALSE)
                                        THEN
                                            // 16#19 Drive object does not exist (access to a drive object that does not exist)
                                            _firstParameterError := 0;
                                            diagnostics.firstParameterError := _firstParameterError;
                                            diagnostics.errorValue := _parameter[0].errorValue;
                                            _status := DriveFunctionStatus#ERR_DO_ID;
                                            _error := TRUE;
                                            _stateNumber := _fBSubState;
                                            _fBState := DriveActDeactStates#FB_ERROR;

                                        ELSIF (_error = FALSE) THEN
                                            // Both parameter are unavailable
                                            _firstParameterError := 0;
                                            diagnostics.firstParameterError := _firstParameterError;
                                            diagnostics.errorValue := _parameter[0].errorValue;
                                            _status := DriveFunctionStatus#ERR_PARAMETER;
                                            _error := TRUE;
                                            _stateNumber := _fBSubState;
                                            _fBState := DriveActDeactStates#FB_ERROR;
                                        END_IF;
                                    END_IF;

                                    ELSIF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_971) OR (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_977) THEN

                                        _parameterRam2Rom[0].format := TO_USINT(_respParameterData[0]);  // Format of the parameter V1.3.3
                                        // Format = Error
                                        IF (((_parameterRam2Rom[0].format > DriveValueFormats#FORMAT_DOUBLE_WORD) OR
                                            ((_parameterRam2Rom[0].format > DriveValueFormats#FORMAT_FLOATING_POINT) AND (_parameterRam2Rom[0].format < DriveValueFormats#FORMAT_OCTET_STRING)) OR
                                            ((_parameterRam2Rom[0].format > DriveValueFormats#FORMAT_OCTET_STRING) AND (_parameterRam2Rom[0].format < DriveValueFormats#FORMAT_TIME_DIFFERENCE)) OR
                                            ((_parameterRam2Rom[0].format > DriveValueFormats#FORMAT_TIME_DIFFERENCE) AND (_parameterRam2Rom[0].format < DriveValueFormats#FORMAT_BYTE)) OR
                                            (_parameterRam2Rom[0].format < DriveValueFormats#FORMAT_INTEGER_8))) AND (_parameterRam2Rom[0].format <> DriveValueFormats#FORMAT_ZERO)
                                        THEN
                                            _parameterRam2Rom[0].errorValue := TO_USINT(_respParameterData[3]);
                                            _firstParameterError := 0;
                                            diagnostics.firstParameterError := _firstParameterError;
                                            diagnostics.errorValue := _parameterRam2Rom[0].errorValue; // V1.3.2
                                            _status := DriveFunctionStatus#ERR_PARAMETER;

                                            _error := TRUE;
                                            _stateNumber := _fBSubState; // V1.3.2
                                            _fBState := DriveActDeactStates#FB_ERROR;

                                        ELSE
                                            // Analyse of the response buffer
                                            CASE _parameterRam2Rom[0].format OF

                                            DriveValueFormats#FORMAT_UNSIGNED_16:
                                                tempWord.%B0 := _respParameterData[3];
                                                tempWord.%B1 := _respParameterData[2];
                                                _parameterRam2Rom[0].realValue := TO_REAL(TO_UINT(tempWord));

                                                _cmdBusy := FALSE;
                                                _cmdError := FALSE;
                                                _status := DriveFunctionStatus#STATUS_BUSY;

                                            ELSE
                                                // Wrong format
                                                _firstParameterError := 0;
                                                diagnostics.firstParameterError := _firstParameterError;
                                                _status := DriveFunctionStatus#ERR_PARAMETER;
                                                _error := TRUE;
                                                _stateNumber := _fBSubState;
                                                _fBState := DriveActDeactStates#FB_ERROR;
                                            END_CASE;

                                            _parameterRam2Rom[0].errorValue := USINT#16#FF; // Sets the error status and diagnostics

                                        END_IF; // Format = Error

                                    ELSE

                                        // Error occurred during writing process (changing parameter values)
                                        IF (_respParameterHeader.reqId = BYTE#16#82) THEN  // reqId: 16#82 (Error occurred during writing parameters)

                                            _parameterRam2Rom[0].errorValue := TO_USINT(_respParameterData[3]);
                                            // Save first parameter error in telegram
                                            // V1.3.2
                                            _firstParameterError := 0;
                                            diagnostics.firstParameterError := _firstParameterError;
                                            diagnostics.errorValue := _parameterRam2Rom[0].errorValue; // V1.3.2

                                            _status := DriveFunctionStatus#ERR_PARAMETER;
                                            _error := TRUE;
                                            _stateNumber := _fBSubState; // V1.3.2
                                            _fBState := DriveActDeactStates#FB_ERROR;

                                        END_IF; // Error occurred during writing process (changing parameter values)
                                    END_IF; // _cmdError = TRUE

                                    IF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_971) AND (_error = FALSE) THEN
                                        _fBSubStateOld := DriveRamToRomStates#FB_BUSY_CHECK_PARAM_971;
                                        _fBSubState := DriveRamToRomStates#FB_BUSY_CYCLE_TIMER;

                                    ELSIF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_971) AND (_error = FALSE) THEN
                                        _fBSubStateOld := DriveRamToRomStates#FB_BUSY_CHECK_PARAM_971;
                                        _fBSubState := DriveRamToRomStates#FB_BUSY_CHECK_PROGRESS;

                                    ELSIF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_WRITE_PARAM_977) AND (_error = FALSE) THEN
                                        _fBSubStateOld := DriveRamToRomStates#FB_BUSY_CHECK_PARAM_977;
                                        _fBSubState := DriveRamToRomStates#FB_BUSY_CYCLE_TIMER;

                                    ELSIF (_fBSubState = DriveRamToRomStates#FB_BUSY_ReadRecord_CHECK_977) AND (_error = FALSE) THEN
                                        _fBSubStateOld := DriveRamToRomStates#FB_BUSY_CHECK_PARAM_977;
                                        _fBSubState := DriveRamToRomStates#FB_BUSY_CHECK_PROGRESS;

                                    END_IF;
                                END_IF; // _cmdError = TRUE
                            ELSE
                                _error := TRUE;
                                _stateNumber := _fbSubState;
                                _status := DriveFunctionStatus#ERR_MISSMATCH_READ_BUFFER_SIZE;
                                _fbState := DriveActDeactStates#FB_ERROR;
                            END_IF;

                        DriveRamToRomStates#FB_BUSY_WAIT:
                            // Timer for temporary errors
                            _instOnDelay(signal := _timerStart,
                                        duration := TIMER_TEMP_ERROR);

                            _timerStart := TRUE;

                            IF (_instOnDelay.output = TRUE) THEN
                                _timerStart := FALSE;
                                _fBSubState := _fBSubStateOld;
                            END_IF;
                        ELSE
                            _error := TRUE;
                            _status := DriveFunctionStatus#ERR_UNDEFINED_SUBSTATE;
                            _stateNumber := _fBSubState; // V1.3.2
                            _fBState := DriveActDeactStates#FB_ERROR;
                    END_CASE;

                ELSE
                    _error := TRUE;
                    _status := DriveFunctionStatus#ERR_COMMAND_TIMEOUT;
                    _stateNumber := _fBSubState; // V1.3.2
                    _fBState := DriveActDeactStates#FB_ERROR;
                END_IF; // ((#buffer.element[_allocatedIndex].enable = TRUE) AND (_mode = #MODE_WITH_BUFFER_MANAGER)) OR _mode = #MODE_WITHOUT_BUFFER_MANAGER

                DriveActDeactStates#FB_RELEASE:
                    // Check buffer index for correctness
                    IF (_allocatedIndex < 0) OR (_allocatedIndex > requestBufferHeader.bufferUpperBound) THEN
                        _error := TRUE;
                        _status := DriveFunctionStatus#ERR_INVALID_BUF_INDEX;
                        _stateNumber := _fBState;
                        _fBState := DriveActDeactStates#FB_ERROR;

                    ELSIF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.5.1
                        requestBufferHeader.lockBuffer := TRUE;
                        IF (requestBuffer[_allocatedIndex].state.%X0 = TRUE) THEN
                            requestBuffer[_allocatedIndex].state.%X2 := TRUE;
                        ELSE
                            ;
                        END_IF;

                        requestBufferHeader.lockBuffer := FALSE;
                        _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
                        _fBState := DriveActDeactStates#FB_DONE;

                    END_IF;
            ELSE
                _error := TRUE;
                _status := DriveFunctionStatus#ERR_UNDEFINED_STATE;
                _stateNumber := _fBState;
                _fBState := DriveActDeactStates#FB_ERROR;
            END_CASE;

            // If input execute is set during processing
            IF _warningRetriggering = TRUE AND _error = FALSE THEN
                _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            END_IF;

        END_IF;

        //----------------------------------------------------------------------------------------------
        //Write outputs and error handling
        //----------------------------------------------------------------------------------------------

        // Error occurred in request
        IF (_fBState = DriveActDeactStates#FB_ERROR) THEN

            // Release the allocated element when error occurs
            IF (_stateNumber <> DriveActDeactStates#FB_FIRST_CYCLE) AND (_stateNumber <> DriveActDeactStates#FB_ALLOCATE)
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
        ELSIF (_fBState = DriveActDeactStates#FB_DONE) THEN
            // Output for one cycle minimum
            IF (execute = FALSE) AND (_done = TRUE) THEN
                _done := FALSE;
                _status := DriveFunctionStatus#STATUS_NO_CALL;
                _fBState := DriveActDeactStates#FB_IDLE;

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
USING System.Timer;
USING System.DateTime;
USING Siemens.Simatic.Hardware.Utilities;
USING Siemens.Simatic.Clocks;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        ReadDriveMessagesDateTimeStates : SINT (
            /// Idle state in FB
            FB_IDLE := SINT#0,
            /// Preparing dataset state in FB (alarms)
            FB_ALARMS_DATASET := SINT#1,
            /// Preparing dataset state in FB (faults)
            FB_FAULTS_DATASET := SINT#2,
            /// Preparing dataset state in FB (SI messages )
            FB_SIMESSAGES_DATASET := SINT#3,
            /// State that prepare dataset (r2125) and call ReadDriveParams
            FB_ALARMS_GONE_DATASET := SINT#4,
            /// Call ReadDriveParams and write messages in statBuffer state
            FB_READ_STEP_1 := SINT#5,
            /// Call ReadDriveParams with FALSE state
            FB_READ_STEP_2 := SINT#6,
            /// Sorting state in FB
            FB_SORTING := SINT#10
        ) := FB_IDLE;
    END_TYPE

    ///=============================================================================
	/// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///-----------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Engineering: SIMATIC AX
	/// Restrictions: The drive must be in UTC mode
	/// Requirements: S7-1200 / S7-1500
	///               FB LAcycCom_ResourceManager is required
	/// Functionality: Read alarms, faults and SI messages from SINAMICS drive and
	///                output in structure (newest elements first)
    ///==============================================================================
    FUNCTION_BLOCK ReadDriveMessagesDateTime
        {S7.Extern = ReadWrite}
        VAR_INPUT 
            /// TRUE: Rising edge starts the functionality once
            execute : BOOL;
            /// TRUE: Enable reading of alarms
            alarms : BOOL := TRUE;
            /// TRUE: Enable reading of faults
            faults : BOOL := TRUE;
            /// TRUE: Enable reading of SI messages
            siMessages : BOOL;
            /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
            driveObjectId : INT := -1;
            /// Hardware identifier of the hardware module
            hardwareId : UINT;
        END_VAR
        
        {S7.Extern = ReadOnly}
        VAR_OUTPUT 
            /// TRUE: Commanded action has been completed successfully
            done : BOOL;
            /// TRUE: FB is not finished and new output values can be expected
            busy : BOOL;
            /// TRUE: Rising edge informs that an error occurred during the execution of the FB
            error : BOOL;
            /// Status identifier
            status : DriveFunctionStatus;
            /// Diagnostics structure
            diagnostics : typeDriveDiagnostics;
            /// List of drive messages
            messages : ARRAY[0..MESSAGES_COUNT_UPPER_LIM] OF typeDriveMessage;
        END_VAR
        
        VAR_IN_OUT
            /// Interface for header of request buffer
            requestBufferHeader : typeRequestBufferHeader;
            /// Interface for request buffer
            requestBuffer : ARRAY[*] OF typeRequestBufferElement;
        END_VAR
        
        VAR 
            /// Static value for output busy
            _busy : BOOL;
            /// Static value for output done
            _done : BOOL;
            /// Static value for output error
            _error : BOOL;
            /// Static value for output status
            _status : DriveFunctionStatus;
            /// Old value of execute for edge detection
            _executeOld : BOOL;
            /// States in the function block state machine
            _fbState : ReadDriveMessagesDateTimeStates;
            /// Static variable for input "alarms"
            _alarmsInput : BOOL;
            /// Static variable for input "faults"
            _faultsInput : BOOL;
            /// Static variable for input "siMessages"
            _siMessagesInput : BOOL;
            /// Intern identification number of the drive object
            _driveObjectId : INT;
            /// Intern hardware identifier of the hardware module
            _hardwareId : UINT;
            /// Time varible for comparasion (sorting)
            _dtl : LDATE_AND_TIME;
            /// Index of newest elemet (for sorting)
            _indexNew : DINT;
            /// Offset for statBuffer/ first empty element in statBuffer
            _offset : SINT;
            /// TRUE: At least one of three inputs must be selected
            _warningNoMessages : BOOL;
            /// TRUE: Input execute is set during processing
            _warningRetriggering : BOOL;
            /// TRUE: FB_READ state complete successfully (faults)
            _faultsComplete : BOOL;
            /// TRUE: FB_READ state complete successfully (alarms)
            _alarmsComplete : BOOL;
            /// Static variable represents current message type
            _currentMessage : SINT;
            /// TRUE: this alarm is already gone
            _goneAlarms : ARRAY[0..ELEMENTS_COUNT_UPPER_LIM] OF BOOL;
            /// Dataset for LAcycCom_ReadDriveParams
            _dataset : ARRAY[0..PARAMETER_COUNT_READ_UPPER_LIM] OF typeDriveDatasetRead;
            /// Buffer for store alarms, faults and SI messages
            _buffer : ARRAY[0..MESSAGES_COUNT_UPPER_LIM] OF typeDriveMessage;
            /// Instance of LAcycCom_ReadDriveParams
            _instReadDriveParams : ReadDriveParams;
        END_VAR
        
        VAR_TEMP 
            // Temporary loop index variable
            tempIndex : DINT;
            // Temporary loop variable for sorting
            tempSort : SINT;
            // Temporary UInt variable
            tempUInt : UINT;
            // Temporary variable for date
            tempDate : LDATE;
            // Temporary variable for time
            tempTime : LTIME_OF_DAY;
            // Return value of system function as word
            tempRetValWord : WORD;
            // Temporary DTL variable
            tempDTL : LDATE_AND_TIME;
            // Current Geo Address information
            tempGeoAddr : GeoAddr;
            // Temporary empty diagnostics structure
            tempVoidDiagnostics : typeDriveDiagnostics;
            // Temporary empty message structure
            tempVoidMessage : typeDriveMessage;
        END_VAR
        
        VAR CONSTANT 
            // The DP component addressed via ID or F_ID is not configured (ReadRecord/WriteRecord)
            INT_ERR_NOT_CONFIG : WORD := WORD#16#8093;
            // Data record not known in module. Illegal data record number ≥ 256 (ReadRecord/WriteRecord)
            INT_ERR_NOT_KNOWN : WORD := WORD#16#80B0;
            // Invalid logical start address (ReadRecord/WriteRecord)
            INT_ERR_LOG_START_ADDR : WORD := WORD#16#8090;
            // Offset in dataset for "info" information
            OFFSET_INFO : SINT := SINT#8;
            // Offset in dataset for "Count days" information
            OFFSET_DAYS : SINT := SINT#16;
            // Offset in dataset for "Count ms" information
            OFFSET_MS : SINT := SINT#24;
            // Count of parameters to be read in ReadDriveParams
            PARAMETER_COUNT_READ_UPPER_LIM : INT := 31;
            // Count of elements in one message type
            ELEMENTS_COUNT_UPPER_LIM : INT := 7;
            // Maximum drive object number limited by SINAMICS p101
            MAX_DRIVE_OBJECT_NO : INT := 254;
            // Maxmimum number of messages
            MESSAGES_COUNT_UPPER_LIM : INT := 23;
            // Conversion value for days to ns
            DAYS_TO_NS : LREAL := LREAL#1.0e+9 * 3600 * 24;
        END_VAR

        // Check if FB is triggered
        IF (execute = TRUE) AND (_executeOld = FALSE) AND (_busy = TRUE) THEN
            // Input execute is set during processing
            status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
            _warningRetriggering := TRUE;
            _executeOld := execute;
        
        ELSIF (execute = TRUE) AND (_executeOld = FALSE) THEN
            // First call
            // Functionality is busy
            _busy := TRUE;
            
            // Reset other outputs
            _error := FALSE;
            _done := FALSE;
            _status := DriveFunctionStatus#STATUS_FIRST_CALL;
            status := _status;
            
            busy := _busy;
            error := _error;
            done := _done;
            _executeOld := execute;
            
            // Initialize
            _alarmsInput := alarms;
            _faultsInput := faults;
            _siMessagesInput := siMessages;
            _driveObjectId := driveObjectId;
            _hardwareId := hardwareId;
            _offset := SINT#0;
            _indexNew := 0;
            diagnostics := tempVoidDiagnostics;
            diagnostics.firstParameterError := -1; // V1.3.2
            diagnostics.errorValue := USINT#16#FF; // V1.3.2
            _warningNoMessages := FALSE;
            _warningRetriggering := FALSE;
            _currentMessage := SINT#0;
            _faultsComplete := FALSE;
            _alarmsComplete := FALSE;
            // Set a default value to first entry in dataset
            _dataset[0].errorValue := USINT#16#FF;
            // Set init time for comparison (sorting)
            _dtl := tempDTL;
            
            IF (_driveObjectId > MAX_DRIVE_OBJECT_NO)
                OR (_driveObjectId = 0)
            THEN // V1.5.2
                // Wrong drive object ID at input
                _error := TRUE;
                _status := DriveFunctionStatus#ERR_INVALID_DRIVE_OBJECT_ID;
                RETURN;
            END_IF;
        
            // Clearing static and output area for alarms, faults and SI messages 
            FOR tempIndex := 0 TO MESSAGES_COUNT_UPPER_LIM DO
                _buffer[tempIndex] := tempVoidMessage;
            END_FOR;

            // Write diagnostics
            diagnostics.hardwareId := _hardwareId;
            
            // Call ReadDriveParams with FALSE
            _instReadDriveParams(execute := FALSE,
                                 requestBufferHeader := requestBufferHeader,
                                 requestBuffer := requestBuffer,
                                 dataset := _dataset);
            
            // Check if device hardware address exist
            tempRetValWord := ReadSlotFromHardwareID(hardwareId := _hardwareId,
                                                     geoAddr := tempGeoAddr);

            // Check if everything is okay
            IF tempRetValWord <> WORD#16#0 THEN
                _error := TRUE;
                diagnostics.subfunctionStatus := tempRetValWord;
                _status := DriveFunctionStatus#ERR_GET_LOCAL_DATE_TIME;
                RETURN;
            END_IF;
        
            // Alarms or faults or SI messages
            IF _siMessagesInput = TRUE THEN
                _fbState := ReadDriveMessagesDateTimeStates#FB_SIMESSAGES_DATASET;
            ELSIF _faultsInput = TRUE THEN
                _fbState := ReadDriveMessagesDateTimeStates#FB_FAULTS_DATASET;
            ELSIF _alarmsInput = TRUE THEN
                _fbState := ReadDriveMessagesDateTimeStates#FB_ALARMS_GONE_DATASET;
            ELSE
                // Warning. At least one of three inputs must be selected
                _status := DriveFunctionStatus#STATUS_FINISHED_NO_MSG_SELECTED;
                _fbState := ReadDriveMessagesDateTimeStates#FB_SORTING;
                _warningNoMessages := TRUE;
            END_IF;
            RETURN;
        
        // Check if FB is disabled (falling edge) after job is done or FB is in error state
        ELSIF (execute = FALSE AND _busy = FALSE) AND
        (_error = TRUE OR _done = TRUE)
        THEN
            // Error outputs are reset with falling edge of enable input
            _error := FALSE;
            
            // Enable and busy are reset with falling edge of enable input
            _done := FALSE;
            _busy := FALSE;
            
            // Write outputs
            _status := DriveFunctionStatus#STATUS_NO_CALL;
            status := _status;
            busy := _busy;
            done := _done;
            error := _error;
            _fbState := ReadDriveMessagesDateTimeStates#FB_IDLE;
            
            // Clearing static and output area for alarms, faults and SI messages 
            FOR tempIndex := 0 TO MESSAGES_COUNT_UPPER_LIM DO
                _buffer[tempIndex] := tempVoidMessage;
            END_FOR;

            _executeOld := execute;
            RETURN;
        
        // FB is currently executed and not finished
        ELSIF _busy = TRUE THEN
            _executeOld := execute;
        
        // FB is disabled
        ELSE
            _executeOld := execute;
            RETURN;
        END_IF;

        //----------------------------------------------------------------------------------------------
        IF (_busy = TRUE) AND (_error = FALSE) THEN  // Functionality running
            CASE _fbState OF
                ReadDriveMessagesDateTimeStates#FB_ALARMS_DATASET:
                    // Preparing dataset for ReadDriveParams  
                    // Alarms
                    FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                        tempUInt := TO_UINT(tempIndex);
                        // Index 0 ..7 - r2122 - "Alarm Code"
                        _dataset[tempIndex].parameterNumber := UINT#2122;
                        _dataset[tempIndex].index := tempUInt;
                        // Index 8 ..15 - r2124 - "Alarm Info"
                        _dataset[tempIndex + OFFSET_INFO].parameterNumber := UINT#2124;
                        _dataset[tempIndex + OFFSET_INFO].index := tempUInt;
                        // Index 16 .. 23 - r2145 - "Alarm come time in days"
                        _dataset[tempIndex + OFFSET_DAYS].parameterNumber := UINT#2145;
                        _dataset[tempIndex + OFFSET_DAYS].index := tempUInt;
                        // Index 24 .. 31 - r2123 - "Alarm come time in ms"
                        _dataset[tempIndex + OFFSET_MS].parameterNumber := UINT#2123;
                        _dataset[tempIndex + OFFSET_MS].index := tempUInt;
                    END_FOR;

                    _fbState := ReadDriveMessagesDateTimeStates#FB_READ_STEP_1;
                    _currentMessage := DriveMessageType#ALARM;
                
                ReadDriveMessagesDateTimeStates#FB_FAULTS_DATASET:
                    // Preparing dataset for ReadDriveParams
                    // Faults
                    FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                        tempUInt := TO_UINT(tempIndex);
                        // Index 0 ..7 - r945 - "Fault Code"
                        _dataset[tempIndex].parameterNumber := UINT#945;
                        _dataset[tempIndex].index := tempUInt;
                        // Index 8 ..15 - r949 - "Fault Info"
                        _dataset[tempIndex + OFFSET_INFO].parameterNumber := UINT#949;
                        _dataset[tempIndex + OFFSET_INFO].index := tempUInt;
                        // Index 16 .. 23 - r2130 - "Fault come time in days"
                        _dataset[tempIndex + OFFSET_DAYS].parameterNumber := UINT#2130;
                        _dataset[tempIndex + OFFSET_DAYS].index := tempUInt;
                        // Index 24 .. 31 - r948 - "Fault come time in ms"
                        _dataset[tempIndex + OFFSET_MS].parameterNumber := UINT#948;
                        _dataset[tempIndex + OFFSET_MS].index := tempUInt;
                        _goneAlarms[tempIndex] := FALSE;
                    END_FOR;

                    _fbState := ReadDriveMessagesDateTimeStates#FB_READ_STEP_1;
                    _currentMessage := DriveMessageType#FAULT;
                
                ReadDriveMessagesDateTimeStates#FB_SIMESSAGES_DATASET:
                    // Preparing dataset for ReadDriveParams
                    // SI Messages
                    FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                        tempUInt := TO_UINT(tempIndex);
                        // Index 0 ..7 - r9747 - "SI Code"
                        _dataset[tempIndex].parameterNumber := UINT#9747;
                        _dataset[tempIndex].index := tempUInt;
                        // Index 8 ..15 - r9749 - "SI Info"
                        _dataset[tempIndex + OFFSET_INFO].parameterNumber := UINT#9749;
                        _dataset[tempIndex + OFFSET_INFO].index := tempUInt;
                        // Index 16 .. 23 - r9754- "SI Message come time in days"
                        _dataset[tempIndex + OFFSET_DAYS].parameterNumber := UINT#9754;
                        _dataset[tempIndex + OFFSET_DAYS].index := tempUInt;
                        // Index 24 .. 31 - r9748 - "SI Message come time in ms"
                        _dataset[tempIndex + OFFSET_MS].parameterNumber := UINT#9748;
                        _dataset[tempIndex + OFFSET_MS].index := tempUInt;
                        _goneAlarms[tempIndex] := FALSE;
                    END_FOR;

                    _fbState := ReadDriveMessagesDateTimeStates#FB_READ_STEP_1;
                    _currentMessage := DriveMessageType#SI_MESSAGE;
                    
                ReadDriveMessagesDateTimeStates#FB_ALARMS_GONE_DATASET:
                    IF NOT _instReadDriveParams.busy AND
                        NOT _instReadDriveParams.done AND
                        NOT _instReadDriveParams.error
                    THEN
                        // Prepare dataset
                        FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                            tempUInt := TO_UINT(tempIndex);
                            // Index 0..7 - r2125 - "Alarm time removed in milliseconds"
                            _dataset[tempIndex].parameterNumber := UINT#2125;
                            _dataset[tempIndex].index := tempUInt;
                        END_FOR;
                    END_IF;
                
                    // Call ReadDriveParams         
                    _instReadDriveParams(execute := TRUE,
                                         parameterCount := ELEMENTS_COUNT_UPPER_LIM + 1, // 8 parameter
                                         driveObjectId := _driveObjectId,
                                         hardwareId := _hardwareId,
                                         requestBufferHeader := requestBufferHeader,
                                         requestBuffer := requestBuffer,
                                         dataset := _dataset);
                
                    IF NOT _instReadDriveParams.busy THEN
                        diagnostics := _instReadDriveParams.diagnostics;
                        IF _instReadDriveParams.done = TRUE THEN
                            // To determine what alarms are already gone
                            FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                                IF _dataset[tempIndex].dwordValue <> DWORD#16#0 THEN
                                    _goneAlarms[tempIndex] := TRUE;
                                ELSE
                                    _goneAlarms[tempIndex] := FALSE; // 01.05.03
                                END_IF;
                            END_FOR;

                            // Call ReadDriveParams with FALSE
                            _instReadDriveParams(execute := FALSE,
                                                 requestBufferHeader := requestBufferHeader,
                                                 requestBuffer := requestBuffer,
                                                 dataset := _dataset);
                            // Go next
                            _fbState := ReadDriveMessagesDateTimeStates#FB_ALARMS_DATASET;
                        
                        ELSIF _instReadDriveParams.error = TRUE THEN
                            _error := TRUE;
                            // HwId is wrong
                            IF (_instReadDriveParams.status = DriveFunctionStatus#ERR_WRITERECORD OR _instReadDriveParams.status = DriveFunctionStatus#ERR_READRECORD) AND
                                ((_instReadDriveParams.diagnostics.subfunctionStatus = INT_ERR_NOT_CONFIG)
                                OR (_instReadDriveParams.diagnostics.subfunctionStatus = INT_ERR_NOT_KNOWN)
                                OR (_instReadDriveParams.diagnostics.subfunctionStatus = INT_ERR_LOG_START_ADDR))
                            THEN
                                _status := DriveFunctionStatus#ERR_HW_ID;
                                // Drive object does not exist
                            ELSIF _dataset[0].errorValue = DriveValueErrors#DRIVE_OBJECT_DOES_NOT_EXIST THEN
                                _status := DriveFunctionStatus#ERR_DO_ID;
                            ELSE
                                _status := DriveFunctionStatus#ERR_READ_DRIVE_PARAMS_ALARMS_GONE;
                            END_IF;
                        END_IF;
                    END_IF;
                
                ReadDriveMessagesDateTimeStates#FB_READ_STEP_1:
                    // Call ReadDriveParams
                    _instReadDriveParams(execute := TRUE,
                                         parameterCount := PARAMETER_COUNT_READ_UPPER_LIM + 1, // 32 parameter
                                         driveObjectId := _driveObjectId,
                                         hardwareId := _hardwareId,
                                         requestBufferHeader := requestBufferHeader,
                                         requestBuffer := requestBuffer,
                                         dataset := _dataset);
                
                    IF NOT _instReadDriveParams.busy THEN
                        diagnostics := _instReadDriveParams.diagnostics;
                        IF _instReadDriveParams.done = TRUE THEN
                            // Copy to static area only elements with content
                            FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                                IF NOT _goneAlarms[tempIndex] THEN
                                    _buffer[_offset].code := TO_UINT(_dataset[tempIndex].dwordValue);
                                    // If parameter empty - then go next
                                    IF _dataset[tempIndex].dwordValue = WORD#16#0 THEN
                                        EXIT;
                                    END_IF;
                                    _buffer[_offset].messageType := _currentMessage; // Identifier for message
                                    _buffer[_offset].info := TO_UDINT(_dataset[tempIndex + OFFSET_INFO].dwordValue);
                                    tempDate := TO_LDATE(TO_LWORD(TO_LINT(_dataset[tempIndex + OFFSET_DAYS].dwordValue) * TO_LINT(DAYS_TO_NS)));
                                    tempTime := TO_LTOD(TO_LWORD(TO_LINT(_dataset[tempIndex + OFFSET_MS].dwordValue) * LINT#1000000));
                                    NewDateAndTime(tempDate, tempTime, _buffer[_offset].comeDateAndTime); // generate LDT format from LDATE and LTIME_OF_DAY
                                    _offset := _offset + SINT#1;
                                END_IF;
                            END_FOR;
                        
                            // Set "complete" flag
                            CASE _currentMessage OF
                                DriveMessageType#ALARM:
                                    _alarmsComplete := TRUE;
                                DriveMessageType#FAULT:
                                    _faultsComplete := TRUE;
                            ELSE
                                ;
                            END_CASE;

                            // Go next step
                            _fbState := ReadDriveMessagesDateTimeStates#FB_READ_STEP_2;
                        
                        // Error while reading  with ReadDriveParams
                        ELSIF _instReadDriveParams.error = TRUE THEN
                            _error := TRUE;
                            // HwId is wrong
                            IF (_instReadDriveParams.status = DriveFunctionStatus#ERR_WRITERECORD OR _instReadDriveParams.status = DriveFunctionStatus#ERR_READRECORD) AND
                                ((_instReadDriveParams.diagnostics.subfunctionStatus = INT_ERR_NOT_CONFIG)
                                OR (_instReadDriveParams.diagnostics.subfunctionStatus = INT_ERR_NOT_KNOWN)
                                OR (_instReadDriveParams.diagnostics.subfunctionStatus = INT_ERR_LOG_START_ADDR))
                            THEN
                                _status := DriveFunctionStatus#ERR_HW_ID;
                                // Drive object does not exist
                            ELSIF _dataset[0].errorValue = DriveValueErrors#DRIVE_OBJECT_DOES_NOT_EXIST THEN
                                _status := DriveFunctionStatus#ERR_DO_ID;
                            ELSE
                                CASE _currentMessage OF
                                    DriveMessageType#ALARM:
                                        _status := DriveFunctionStatus#ERR_READ_DRIVE_PARAMS_ALARMS;
                                    DriveMessageType#FAULT:
                                        _status := DriveFunctionStatus#ERR_READ_DRIVE_PARAMS_FAULTS;
                                    DriveMessageType#SI_MESSAGE:
                                        _status := DriveFunctionStatus#ERR_READ_DRIVE_PARAMS_SI_MESSAGES;
                                ELSE
                                    ;
                                END_CASE;
                            END_IF;
                        END_IF;
                    END_IF;
                
                ReadDriveMessagesDateTimeStates#FB_READ_STEP_2:
                    // Call ReadDriveParams with FALSE
                    _instReadDriveParams(execute := FALSE,
                                         requestBufferHeader := requestBufferHeader,
                                         requestBuffer := requestBuffer,
                                         dataset := _dataset);
                    
                    // Choice next step. Right call order: SI messages, faults, alarms
                    IF _faultsInput AND NOT _faultsComplete THEN
                        _fbState := ReadDriveMessagesDateTimeStates#FB_FAULTS_DATASET;
                    ELSIF (_alarmsInput AND NOT _alarmsComplete) THEN
                        _fbState := ReadDriveMessagesDateTimeStates#FB_ALARMS_GONE_DATASET;
                    ELSE
                        _fbState := ReadDriveMessagesDateTimeStates#FB_SORTING;
                    END_IF;
                
                ReadDriveMessagesDateTimeStates#FB_SORTING:
                    // When at least one message has been read
                    IF _offset <> 0 THEN
                        // Sorting algorithm. Newest message - first
                        // When more then two messages of different type have the same come time, then order sequence is - alarms, faults, SI messages
                        FOR tempSort := 0 TO (_offset - SINT#1) DO
                            // Find newest element
                            FOR tempIndex := 0 TO (_offset - 1) DO
                                IF _buffer[tempIndex].comeDateAndTime >= _dtl THEN
                                    _dtl := _buffer[tempIndex].comeDateAndTime;
                                    _indexNew := tempIndex;
                                END_IF;
                            END_FOR;
                        
                            // Copy found element to output structure
                            messages[tempSort] := _buffer[_indexNew];

                            // Remove this element from buffer - by setting the value as small as possible
                            _buffer[_indexNew].comeDateAndTime := tempDTL;
                            // Set init time for next comparison
                            _dtl := tempDTL;
                        END_FOR;
                    END_IF;
                    // Set "done" flag
                    _done := TRUE;  
                ELSE
                    _error := TRUE;
                    _status := DriveFunctionStatus#ERR_UNDEFINED_STATE;
            END_CASE;
        END_IF;

        //----------------------------------------------------------------------------------------------
        // Write outputs and error handling
        //----------------------------------------------------------------------------------------------
        // Error occurred in request
        IF _error = TRUE
        THEN
            _done := FALSE;
            _busy := FALSE;
            // Write diagnostics
            diagnostics.stateNumber := _fbState;
            diagnostics.status := _status;
            
        // Request finished
        ELSIF _done = TRUE
        THEN
            _busy := FALSE;
            _error := FALSE;
            _fbState := ReadDriveMessagesDateTimeStates#FB_IDLE;
            // Set status
            IF _warningRetriggering = TRUE THEN
                // If input execute is set during processing
                _status := DriveFunctionStatus#ERR_AMBIGUOUS_FB_CALL;
                diagnostics.status := _status;
                _error := TRUE;
                _done := FALSE;
            ELSIF _warningNoMessages = FALSE THEN
                // Execution finished without errors
                _status := DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
            ELSE
                // Warning. At least one of three inputs must be selected
                _status := DriveFunctionStatus#STATUS_FINISHED_NO_MSG_SELECTED;
                diagnostics.status := _status;
            END_IF;
        
        // If input execute is set during processing
        ELSIF _warningRetriggering = TRUE
        THEN
            _status := DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
        
        // Request in execution
        ELSE
            _status := DriveFunctionStatus#STATUS_SUBSEQUENT_CALL;
        END_IF;

        // Write static values to outputs
        done := _done;
        busy := _busy;
        error := _error;
        status := _status;
        //----------------------------------------------------------------------------------------------
    END_FUNCTION_BLOCK
END_NAMESPACE
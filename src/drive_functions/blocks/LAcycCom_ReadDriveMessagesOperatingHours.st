USING System.Timer;
USING System.DateTime;
USING System.Math;
USING Siemens.Simatic.Hardware.Utilities;
USING Siemens.Simatic.Clocks;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        ReadDriveMessagesOperatingHoursStates : SINT (
            /// Idle state in FB
            FB_IDLE := SINT#0,
            /// Preparing dataset state in FB (alarms)
            FB_ALARMS_DATASET := SINT#1,
            /// Preparing dataset state in FB (faults)
            FB_FAULTS_DATASET := SINT#2,
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

    ///==============================================================================
    /// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Engineering: SIMATIC AX
	/// Restrictions: The drive must provide operating hours (days + ms)
	/// Requirements: S7-1200 / S7-1500
	///               FB LAcycCom_ResourceManager is required
	/// Functionality: Read alarms and faults from G120 drive (convert operating
	///                hours to "time" in reference to SIMATIC controller) and output
	///                in structure (newest elements first)
    ///==============================================================================
    FUNCTION_BLOCK ReadDriveMessagesOperatingHours
        {S7.Extern = ReadWrite}
        VAR_INPUT
            /// TRUE: Rising edge starts the functionality once
            execute : BOOL;
            /// TRUE: Enable reading of alarms
            alarms : BOOL := TRUE;
            /// TRUE: Enable reading of faults
            faults : BOOL := TRUE;
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
            _fbstate : ReadDriveMessagesOperatingHoursStates;
            /// Static variable for input "alarms"
            _alarmsInput : BOOL;
            /// Static variable for input "faults"
            _faultsInput : BOOL;
            /// Intern identification number of the drive object
            _driveObjectId : SINT;
            /// Intern hardware identifier of the hardware module
            _hardwareId : UINT;
            /// Time varible for comparasion (sorting)
            _dtl : LDATE_AND_TIME;
            /// Index of newest elemet (for sorting)
            _indexNew : DINT;
            /// Offset for statBuffer/ first empty element in statBuffer
            _offset : SINT;
            /// TRUE: At least one of two inputs must be selected
            _warningNoMessages : BOOL;
            /// TRUE: Input execute is set during processing
            _warningRetriggering : BOOL;
            /// TRUE: FB_READ state complete successfully (alarms)
            _alarmsComplete : BOOL;
            /// Static variable represents current message type
            _currentMessage : DriveMessageType;
            /// Current data and current time-of-day of the CPU clock
            _cpuTime : LDATE_AND_TIME;
            /// TRUE: r2124 (represents system runtime total of CU ) is not yet read and evaluate
            _cuTimeNotRead : BOOL;
            /// TRUE: CPU time is not yet read
            _cpuTimeNotRead : BOOL;
            /// Static variable represents r2124[0] - ms, convert to TOD
            _driveObjectTOD : TIME_OF_DAY;
            /// Static variable represents r2124[1] - days
            _driveObjectDays : DINT;
            /// Difference in days between actual time from system runtime counter and time from come message
            _diffDays : DINT;
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
            // Temporary variable for days
            tempDriveObjectDays : DINT;
            // Temporary variable for data type TOD
            tempDriveObjectTOD : TIME_OF_DAY;
            /// Temporary variable for days
            tempDays : DINT;
            /// Temporary variable for time of day
            tempTOD : TIME_OF_DAY;
            // Return value of system function
            tempRetValWord : WORD;
            // Temporary variable for quititent
            tempQuitient : DINT;
            // Temporary variable for remainder
            tempRemainder : DINT;
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
            // Drive object does not exist
            DO_NOT_EXIST : WORD := WORD#16#0019;
            // Offset in dataset for "info" information
            OFFSET_INFO : SINT := SINT#8;
            // Offset in dataset for "Count days" information
            OFFSET_DAYS : SINT := SINT#16;
            // Offset in dataset for "Count ms" information
            OFFSET_MS : SINT := SINT#24;
            // Count of parameters to be read in ReadDriveParams
            PARAMETER_COUNT_READ_UPPER_LIM : INT := INT#33;
            // Count of elements in one message type
            ELEMENTS_COUNT_UPPER_LIM : INT := INT#7;
            // Max count of days of data type "Time"
            MAX_COUNT_DAYS : DINT := DINT#24;
            // Drive object ID for G120 (e.g. CU240)
            DRIVE_OBJECT_ID_G120 : SINT := SINT#1;
            // Upper limit of elements in LAcycCom_typeDriveMessages
            MESSAGES_UPPER_LIM_LOCAL : INT := INT#15;
            // Constant to conversion from days to ms (1000*60*60*24)
            DAYS_TO_MS : DINT := DINT#86400000;
            // Maxmimum number of messages
            MESSAGES_COUNT_UPPER_LIM : INT := INT#23;
            // Conversion value for days to ns
            TO_NS : LREAL := LREAL#1.0e+9 * 3600 * 24;
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
            _driveObjectId := DRIVE_OBJECT_ID_G120;
            _hardwareId := hardwareId;
            _offset := SINT#0;
            _indexNew := SINT#0;
            diagnostics := tempVoidDiagnostics;
            diagnostics.firstParameterError := -1; // V1.3.2
            diagnostics.errorValue := USINT#16#FF; // V1.3.2
            _warningNoMessages := FALSE;
            _warningRetriggering := FALSE;
            _currentMessage := DriveMessageType#ALARM;
            _alarmsComplete := FALSE;
            // Set a default value to first entry in dataset
            _dataset[0].errorValue := USINT#16#FF;
            // Set init time for comparison (sorting)
            _dtl := tempDTL;
            _cpuTimeNotRead := TRUE;
            _cuTimeNotRead := TRUE;

            // Clearing static and output area for alarms, faults and SI messages 
            FOR tempIndex := 0 TO MESSAGES_COUNT_UPPER_LIM DO
                _buffer[tempIndex] := tempVoidMessage;
            END_FOR;

            // Write diagnostics
            diagnostics.hardwareId := _hardwareId;
            diagnostics.driveObjectId := _driveObjectId;
        
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
                _status := DriveFunctionStatus#ERR_HW_ID;
                RETURN;
            END_IF;
        
            // Alarms or faults
            IF _faultsInput = TRUE THEN
                _fbstate := ReadDriveMessagesOperatingHoursStates#FB_FAULTS_DATASET;
            ELSIF _alarmsInput = TRUE THEN
                _fbstate := ReadDriveMessagesOperatingHoursStates#FB_ALARMS_GONE_DATASET;
            ELSE
                // Warning. At least one of two inputs must be selected
                _status := DriveFunctionStatus#STATUS_FINISHED_NO_MSG_SELECTED;
                _fbstate := ReadDriveMessagesOperatingHoursStates#FB_SORTING;
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
            _fbstate := ReadDriveMessagesOperatingHoursStates#FB_IDLE;
            
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
            CASE _fbstate OF
                
                ReadDriveMessagesOperatingHoursStates#FB_ALARMS_DATASET:
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
                
                    // r2114 - System Runtime Total. Index 32 and 33
                    _dataset[32].parameterNumber := UINT#2114;
                    _dataset[32].index := UINT#0;    // ms
                    _dataset[33].parameterNumber := UINT#2114;
                    _dataset[33].index := UINT#1;  // Days
                    _fbstate := ReadDriveMessagesOperatingHoursStates#FB_READ_STEP_1;
                    _currentMessage := DriveMessageType#ALARM;
                
                ReadDriveMessagesOperatingHoursStates#FB_FAULTS_DATASET:
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

                    // r2114 - System Runtime Total. Index 32 and 33
                    _dataset[32].parameterNumber := UINT#2114;
                    _dataset[32].index := UINT#0;    // ms
                    _dataset[33].parameterNumber := UINT#2114;
                    _dataset[33].index := UINT#1;  // Days
                    _fbstate := ReadDriveMessagesOperatingHoursStates#FB_READ_STEP_1;
                    _currentMessage := DriveMessageType#FAULT;
                
                ReadDriveMessagesOperatingHoursStates#FB_ALARMS_GONE_DATASET:
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
                                         parameterCount := ELEMENTS_COUNT_UPPER_LIM + 1, //8 parameter
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
                                IF _dataset[tempIndex].dwordValue <> WORD#16#0 THEN
                                    _goneAlarms[tempIndex] := TRUE;
                                ELSE
                                    _goneAlarms[tempIndex] := FALSE; // 01.05.02
                                END_IF;
                            END_FOR;

                            // Call ReadDriveParams with FALSE
                            _instReadDriveParams(execute := FALSE,
                                                 requestBufferHeader := requestBufferHeader,
                                                 requestBuffer := requestBuffer,
                                                 dataset := _dataset);
                            // Go next
                            _fbstate := ReadDriveMessagesOperatingHoursStates#FB_ALARMS_DATASET;
                        
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
                
                
                ReadDriveMessagesOperatingHoursStates#FB_READ_STEP_1:
                    IF _cpuTimeNotRead = TRUE THEN
                        // Read CPU time
                        tempRetValWord := GetLocalDateTime(_cpuTime); // Reading current date and time of cpu clock

                        // Error occurred during RD_LOC_T command
                        IF (tempRetValWord <> WORD#16#0) AND (tempRetValWord <> WORD#16#0001) THEN
                            _error := TRUE;
                            diagnostics.subfunctionStatus := tempRetValWord;
                            _status := DriveFunctionStatus#ERR_GET_LOCAL_DATE_TIME;
                        END_IF;
                        _cpuTimeNotRead := FALSE;
                    END_IF;
                
                    // Call ReadDriveParams
                    _instReadDriveParams(execute := TRUE,
                                         parameterCount := PARAMETER_COUNT_READ_UPPER_LIM + 1, //34 parameter = 32 parameter for messages + 2 parameter for "System Runtime Total" r2124[0] and r2124[1]
                                         driveObjectId := _driveObjectId,
                                         hardwareId := _hardwareId,
                                         requestBufferHeader := requestBufferHeader,
                                         requestBuffer := requestBuffer,
                                         dataset := _dataset);
                
                    IF NOT _instReadDriveParams.busy THEN
                        diagnostics := _instReadDriveParams.diagnostics;
                        IF _instReadDriveParams.done = TRUE THEN
                            // CU Time from parameter r2124
                            IF _cuTimeNotRead = TRUE THEN
                                _driveObjectDays := TO_DINT(_dataset[33].dwordValue);   // Days as DINT
                                _driveObjectTOD := TO_TOD(TO_LWORD(TO_LINT(_dataset[32].dwordValue) * LINT#1000000)); // ms convert to TOD
                                _cuTimeNotRead := FALSE;
                            END_IF;
                        
                            // Copy to static area only elements with content
                            FOR tempIndex := 0 TO ELEMENTS_COUNT_UPPER_LIM DO
                                IF NOT _goneAlarms[tempIndex] THEN
                                    _buffer[_offset].code := TO_UINT(_dataset[tempIndex].dwordValue);
                                    // If parameter empty - then go next
                                    IF _dataset[tempIndex].dwordValue = WORD#16#0 THEN
                                        EXIT;
                                    END_IF;

                                    _buffer[_offset].info := TO_UDINT(_dataset[tempIndex + OFFSET_INFO].dwordValue);
                                    tempDriveObjectDays := TO_DINT(_dataset[tempIndex + OFFSET_DAYS].dwordValue);
                                    tempDriveObjectTOD := TO_TOD(TO_LWORD(_dataset[tempIndex + OFFSET_MS].dwordValue));
                                    //=======================================================================================================================================
                                    // Calcutation "come Date and Time" of G120. This CUs (all G120 except CU230P-2) have only system runtime counter...
                                    // comeDateAndTime = CPU Time(statCPUTime) - (difference statCUDays and tempDays) - (difference statCUTOD and tempTOD)
                                    _diffDays := _driveObjectDays - tempDriveObjectDays; // Difference in days between actual time from system runtime counter and time from come message
                                    _buffer[_offset].comeDateAndTime := _cpuTime;
                                    IF ABS(_diffDays) <= MAX_COUNT_DAYS THEN  // Max value of variable Time is T#24d
                                        tempDays := (TO_DINT(TO_LWORD(_buffer[_offset].comeDateAndTime)) / DAYS_TO_MS) - _diffDays; // Difference drive object days to diff days
                                        tempTOD := TO_TOD(_buffer[_offset].comeDateAndTime); // extract time of day from buffer
                                        NewDateAndTime(TO_LDATE(TO_LWORD(tempDays)), TO_LTOD(tempTOD), _buffer[_offset].comeDateAndTime); // create new date and time based on day difference and current time of day

                                    ELSE // When count of days > 24 then must be sliced
                                        tempQuitient := _diffDays / MAX_COUNT_DAYS;
                                        tempRemainder := _diffDays MOD MAX_COUNT_DAYS;
                                            FOR tempSort := 1 TO TO_SINT(tempQuitient) DO
                                            tempDays := (TO_DINT(TO_LWORD(_buffer[_offset].comeDateAndTime)) / DAYS_TO_MS) - (MAX_COUNT_DAYS * DAYS_TO_MS);
                                            tempTOD := TO_TOD(_buffer[_offset].comeDateAndTime); // extract time of day from buffer
                                            NewDateAndTime(TO_LDATE(TO_LWORD(tempDays)), TO_LTOD(tempTOD), _buffer[_offset].comeDateAndTime); // create new date and time based on day difference and current time of day
                                        END_FOR;                    
                                        tempDays := (TO_DINT(TO_LWORD(_buffer[_offset].comeDateAndTime)) / DAYS_TO_MS) - (tempRemainder * DAYS_TO_MS); // Difference statCUDays and tempDays in format Time
                                        tempTOD := TO_TOD(_buffer[_offset].comeDateAndTime); // extract time of day from buffer
                                        NewDateAndTime(TO_LDATE(TO_LWORD(tempDays)), TO_LTOD(tempTOD), _buffer[_offset].comeDateAndTime);
                                    END_IF;

                                    // tempTime := T_DIFF(IN1 := statDriveObjectTOD, IN2 := tempDriveObjectTOD); // Difference statCUTOD and tempTOD in format Time - ms
                                    // statBuffer.comeDateAndTime[statOffset] := T_SUB(IN1 := statBuffer.comeDateAndTime[statOffset], IN2 := tempTime); // Subtraction ms    

                                    tempDays := TO_DINT(TO_LWORD(_driveObjectTOD)) - TO_DINT(TO_LWORD(tempDriveObjectTOD)) / DAYS_TO_MS; // Difference statCUTOD and tempTOD in format Time - ms
                                    tempTOD := TO_TOD(_buffer[_offset].comeDateAndTime); // extract time of day from buffer
                                    NewDateAndTime(TO_LDATE(TO_LWORD(tempDays)), TO_LTOD(tempTOD), _buffer[_offset].comeDateAndTime);

                                    //=======================================================================================================================================
                                    _buffer[_offset].messageType := _currentMessage; // Identifier for message
                                    _offset := _offset + SINT#1;
                                END_IF;
                            END_FOR;

                        // Set "complete" flag
                        IF _currentMessage = DriveMessageType#ALARM THEN
                            _alarmsComplete := TRUE;
                        END_IF;
                        
                        // Go next step
                        _fbstate := ReadDriveMessagesOperatingHoursStates#FB_READ_STEP_2;
                        
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
                            ELSE
                                ;
                            END_CASE;
                        END_IF;              
                    END_IF;
                END_IF;
                
                ReadDriveMessagesOperatingHoursStates#FB_READ_STEP_2:
                    // Call ReadDriveParams with FALSE
                    _instReadDriveParams(execute := FALSE,
                                         requestBufferHeader := requestBufferHeader,
                                         requestBuffer := requestBuffer,
                                         dataset := _dataset);
                
                    // Choice next step. Right call order: faults, alarms
                    IF (_alarmsInput AND NOT _alarmsComplete) THEN
                        _fbstate := ReadDriveMessagesOperatingHoursStates#FB_ALARMS_GONE_DATASET;
                    ELSE
                        _fbstate := ReadDriveMessagesOperatingHoursStates#FB_SORTING;
                    END_IF;
                
                
                ReadDriveMessagesOperatingHoursStates#FB_SORTING:
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
            diagnostics.stateNumber := _fbstate;
            diagnostics.status := _status;
        
        // Request finished
        ELSIF _done = TRUE THEN
            _busy := FALSE;
            _error := FALSE;
            _fbstate := ReadDriveMessagesOperatingHoursStates#FB_IDLE;
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
                // Warning. At least one of two inputs must be selected
                _status := DriveFunctionStatus#STATUS_FINISHED_NO_MSG_SELECTED;
                diagnostics.status := _status;
            END_IF;
            
        // If input execute is set during processing
        ELSIF _warningRetriggering = TRUE THEN
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
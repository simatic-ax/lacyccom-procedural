NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_typeAckDriveFaultsStates : SINT (
      FB_IDLE := SINT#0,   // Idle state in FB
      FB_BUSY := SINT#1   // Busy state in FB
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
	/// Functionality: Sets parameter p3981 for fault acknowledgement.
  ///------------------------------------------------------------------------------------------
  FUNCTION_BLOCK LAcycCom_AckDriveFaults
    {S7.Extern = ReadWrite}
    VAR_INPUT
      execute : BOOL;   /// TRUE: Rising edge starts the functionality once
      driveObjectId : INT := -1;   /// Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId)
      hardwareId : UINT;   /// Hardware identifier of the hardware module
    END_VAR

    {S7.Extern = ReadOnly}
    VAR_OUTPUT
      done : BOOL;   /// TRUE: Commanded action has been completed successfully
      busy : BOOL;   /// TRUE: FB is not finished and new output values can be expected
      error : BOOL;   /// TRUE: Rising edge informs that an error occurred during the execution of the FB
      status : LAcycCom_DriveFunctionStatus;   /// Status identifier
      diagnostics : LAcycCom_typeDriveDiagnostics;   /// Diagnostics structure
    END_VAR

    VAR_IN_OUT
      requestBufferHeader : LAcycCom_typeRequestBufferHeader;   /// Interface for header of request buffer
      requestBuffer : ARRAY[*] OF LAcycCom_typeRequestBufferElement;   /// Interface for request buffer
    END_VAR

    VAR
      _executeOld : BOOL := FALSE;   /// Old value of execute for edge detection
      _busy : BOOL := FALSE;   /// Static value for output busy
      _done : BOOL := FALSE;   /// Static value for output done
      _error : BOOL := FALSE;   /// Static value for output error
      _fbState : LAcycCom_typeAckDriveFaultsStates;   /// States in the function block state machine
      _driveObjectId : INT;   /// Intern identification number of the drive object
      _hardwareId : UINT;   /// Intern hardware identifier of the hardware module
      _warningRetriggering : BOOL;   /// TRUE: Input execute is set during processing
      _instWriteDriveSingleParam : LAcycCom_WriteDriveSingleParam;   /// Instance of LAcycCom_WriteSingleDriveParam
    END_VAR

    VAR_TEMP
      tempVoidDiagnostics : LAcycCom_typeDriveDiagnostics;   // Temporary empty diagnostics structure
    END_VAR

    VAR CONSTANT
      MAX_DRIVE_OBJECT_NO : INT := 254;   // Maximum drive object number limited by SINAMICS p101
      FAULTS_ACKNOWLEDGE : UINT := UINT#3981;   // Faults acknowledge drive object
    END_VAR

    // Check if FB is triggered
    IF (execute = TRUE) AND (_executeOld = FALSE) AND (_busy = TRUE) THEN
      // Input execute is set during processing
      status := LAcycCom_DriveFunctionStatus#WARN_EXECUTE_SET_DURING_PROCESSING;
      _warningRetriggering := TRUE;
      _executeOld := execute;
      
    ELSIF (execute = TRUE) AND (_executeOld = FALSE) THEN
      // First call
      // Functionality is busy
      _busy := TRUE;
      
      // Reset other outputs
      _error := FALSE;
      _done := FALSE;
      status := LAcycCom_DriveFunctionStatus#STATUS_BUSY;
      
      busy := _busy;
      error := _error;
      done := _done;
      _executeOld := execute;
      // Initialize
      _fbState := LAcycCom_typeAckDriveFaultsStates#FB_BUSY;
      _driveObjectId := driveObjectId;
      _hardwareId := hardwareId;
      _instWriteDriveSingleParam(execute := FALSE,
                                 requestBufferHeader := requestBufferHeader,
                                 requestBuffer := requestBuffer);
      diagnostics := tempVoidDiagnostics;
      diagnostics.firstParameterError := -1; // V1.3.2
      diagnostics.errorValue := BYTE#16#FF; // V1.3.2
      _warningRetriggering := FALSE;
      
      IF (_driveObjectId > MAX_DRIVE_OBJECT_NO)
        OR (_driveObjectId = 0)
      THEN // V1.5.2
        // Wrong drive object ID at input
        _error := TRUE;
        status := LAcycCom_DriveFunctionStatus#ERR_INVALID_DRIVE_OBJECT_ID;
        RETURN;
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
      status := LAcycCom_DriveFunctionStatus#STATUS_NO_CALL;
      busy := _busy;
      done := _done;
      error := _error;
      _fbState := LAcycCom_typeAckDriveFaultsStates#FB_IDLE;
      
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
    IF (_busy = TRUE) AND (_error = FALSE) THEN
      CASE _fbState OF
        LAcycCom_typeAckDriveFaultsStates#FB_BUSY:
          // Call WriteDriveParams
          _instWriteDriveSingleParam(execute := TRUE,
                                     driveObjectId := _driveObjectId,
                                     hardwareId := _hardwareId,
                                     parameterNumber := FAULTS_ACKNOWLEDGE,
                                     writeSelector := LAcycCom_DatatypeSelector#TYPE_DWORD,
                                     dwordValue := DWORD#1,
                                     requestBufferHeader := requestBufferHeader,
                                     requestBuffer := requestBuffer);
          
          IF NOT _instWriteDriveSingleParam.busy THEN
            diagnostics := _instWriteDriveSingleParam.diagnostics;
            
            IF _instWriteDriveSingleParam.done = TRUE THEN
              _done := TRUE;
            ELSIF _instWriteDriveSingleParam.error = TRUE THEN
              status := _instWriteDriveSingleParam.status;
              diagnostics := _instWriteDriveSingleParam.diagnostics;
              _error := TRUE;
            END_IF;
          END_IF;
          
          
        ELSE
          _error := TRUE;
          status := LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_STATE;
          diagnostics.status := LAcycCom_DriveFunctionStatus#ERR_UNDEFINED_STATE;
      END_CASE;
    END_IF;
    
    //----------------------------------------------------------------------------------------------
    // Write outputs and error handling
    //----------------------------------------------------------------------------------------------
    // Error occurred in request
    IF _error = TRUE THEN
      _done := FALSE;
      _busy := FALSE;
      diagnostics.stateNumber := _fbState;
      
      // Request finished
    ELSIF _done = TRUE THEN
      _error := FALSE;
      _busy := FALSE;
      _fbState := LAcycCom_typeAckDriveFaultsStates#FB_IDLE;
      IF _warningRetriggering = FALSE THEN
        status := LAcycCom_DriveFunctionStatus#STATUS_EXECUTION_FINISHED;
      ELSE
        // If input execute is set during processing
        status := LAcycCom_DriveFunctionStatus#ERR_AMBIGUOUS_FB_CALL;
        diagnostics.status := LAcycCom_DriveFunctionStatus#ERR_AMBIGUOUS_FB_CALL;
        _error := TRUE;
        _done := FALSE;
      END_IF;
    END_IF;
    
    // Write static values to outputs
    error := _error;
    busy := _busy;
    done := _done;
    //----------------------------------------------------------------------------------------------
  END_FUNCTION_BLOCK
END_NAMESPACE
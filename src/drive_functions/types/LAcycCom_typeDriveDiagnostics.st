NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Contains diagnostics information about the drive function blocks, internal state and various relevant information
    LAcycCom_typeDriveDiagnostics : STRUCT
      status : WORD := WORD#16#0000;   /// Status identifier when error occurred
      subfunctionStatus : WORD := WORD#16#0000;   /// Block status or error information
      stateNumber : SINT := SINT#0;   /// State of the FB when error occurred
      driveObjectId : SINT := SINT#0;   /// Identification number of the drive object
      hardwareId : UINT := UINT#0;   /// Hardware identifier of the hardware module
      parameterCount : INT := 0;   /// Total amount of parameters
      firstParameterError : INT := -1;   /// Number of parameter at which the error occurred (-1: no parameter with error)
      errorValue : BYTE := BYTE#16#FF;   /// Error number (16#FF: no error; else: see error list)
    END_STRUCT;
  END_TYPE
END_NAMESPACE
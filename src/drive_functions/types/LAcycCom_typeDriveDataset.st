NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Defines an universal dataset of the drive (parameter, index, value and an error value) that can be either read via LAcycCom_ReadDriveParams or written via LAcycCom_WriteDriveParams
    LAcycCom_typeDriveDataset : STRUCT
      parameterNumber : UINT := UINT#0;          /// Number of the parameter
      index : UINT := UINT#0;                    /// Parameter index
      writeSelector : LAcycCom_DatatypeSelector; /// LAcycCom_ReadDriveParams: no function; LAcycCom_WriteDriveParams: type selector to specify the value of this dataset that will be written to the parameter
      realValue : REAL := REAL#0.0;              /// Parameter value as real
      dwordValue : DWORD := DWORD#16#0;          /// Parameter value as dword
      // todo: https://code.siemens.com/axpc/libraries/lacyccom/lib/-/issues/2
      // lrealValue : LREAL := 0.0;                 /// Parameter value as lreal
      errorValue : BYTE := BYTE#16#FF;           /// Error number (16#FF: no error; else: see error list)
    END_STRUCT;
  END_TYPE
END_NAMESPACE
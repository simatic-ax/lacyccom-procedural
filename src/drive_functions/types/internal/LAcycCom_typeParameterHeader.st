NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_typeParameterHeader : STRUCT
      refNo : BYTE;   // Request reference (Request ID, mirrored in response)
      reqId : BYTE;   // Request ID 0x1=Read
      doId : BYTE;   // Identifier number of the drive object
      parameterNo : BYTE;   // Number of parameters (for single parameters=1)
    END_STRUCT;
  END_TYPE
END_NAMESPACE
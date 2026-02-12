NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_typeParameter : STRUCT
      parameterNo : UINT;   // Number of parameter (Number 1..65535)
      index : UINT;   // Subindex (Number 1..65535)
      realValue : REAL;   // Value of parameter (Real)
      dwordValue : DWORD;   // Value of parameter (DWord)
      format : BYTE;   // Format of value
      errorValue : BYTE;   // Error number (16#FF: no error; else: see error list)
    END_STRUCT;
  END_TYPE
END_NAMESPACE
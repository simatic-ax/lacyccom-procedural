NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_typeParameterAddress : STRUCT
      attribute : BYTE;   // Attribute of parameters (0x10=Value, 0x30=Text)
      elementNo : BYTE;   // Number of elements (for single elements=1)
      parameterNo : UINT;   // Number of parameter (Number 1..65535)
      index : UINT;   // Subindex (Number 1..65535)
    END_STRUCT;
  END_TYPE
END_NAMESPACE
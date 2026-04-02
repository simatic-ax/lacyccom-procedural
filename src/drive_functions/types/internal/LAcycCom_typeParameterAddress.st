NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        typeParameterAddress : STRUCT
            /// Attribute of parameters (16#10 = Value, 16#20 = Description, 16#30 = Text)
            attribute : BYTE;
            /// Number of elements (for single elements = 1)
            elementNo : BYTE;
            /// Number of parameter (Number 1..65535)
            parameterNo : UINT;
            /// Subindex (Number 1..65535)
            index : UINT;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        typeParameter : STRUCT
            /// Number of parameter (Number 1..65535)
            parameterNo : UINT;
            /// Subindex (Number 1..65535)
            index : UINT;
            /// Value of parameter (Real)
            realValue : REAL;
            /// Value of parameter (DWord)
            dwordValue : DWORD;
            /// Value of parameter (LReal)
            lrealValue: LREAL;
            /// Format of value
            format : USINT;
            /// Error value
            errorValue : USINT;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
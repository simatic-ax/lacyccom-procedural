NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        typeParameterHeader : STRUCT
            /// Request reference (Request ID, mirrored in response to identify the request)
            refNo : BYTE;
            /// Request ID (16#01 = Read, 16#02 = Write)
            reqId : BYTE;
            /// Identifier number of the drive object (Target DO)
            doId : BYTE;
            /// Number of parameters in this request (1..37)
            parameterNo : BYTE;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
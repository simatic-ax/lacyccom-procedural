NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Defines a drive data set to read drive parameters via LAcycCom_WriteReadParams
        typeDriveDatasetRead : STRUCT
            /// Number of the parameter
            parameterNumber : UINT := UINT#0;
            /// Parameter index
            index : UINT := UINT#0;
            /// Parameter value as real
            realValue : REAL := REAL#0.0;
            /// Parameter value as dword
            dwordValue : DWORD := WORD#16#0;
            /// Parameter value as lreal
            lrealValue : LREAL := LREAL#0.0;
            /// Error number (16#FF: no error; else: see error list)
            errorValue : DriveValueErrors := USINT#16#FF;
            /// Format of the value
            format : DriveValueFormats;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
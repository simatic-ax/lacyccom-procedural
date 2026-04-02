NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Defines a drive data set to write drive parameters via LAcycCom_WriteDriveParams
        typeDriveDatasetWrite : STRUCT
            /// Number of the parameter
            parameterNumber : UINT := UINT#0;
            /// Parameter index
            index : UINT := UINT#0;
            /// Type selector to specify the value of this dataset that will be written to the parameter
            valueSelector : DatatypeSelector;
            /// Parameter value as real
            realValue : REAL := REAL#0.0;
            /// Parameter value as dword
            dwordValue : DWORD := WORD#16#0;
            /// Parameter value as lreal
            lrealValue : LREAL := LREAL#0.0;
            /// Error value (16#FF: no error)
            errorValue : USINT := USINT#16#FF;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
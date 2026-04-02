NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Contains diagnostics information about the drive function blocks, internal state and various relevant information
        typeDriveDiagnostics : STRUCT
            /// Status identifier when error occurred (Internal FB Status)
            status : WORD := WORD#16#0000;
            /// Block status or error information (e.g., from RDREC/WRREC)
            subfunctionStatus : WORD := WORD#16#0000;
            /// State of the FB state machine when the error occurred
            stateNumber : SINT := SINT#0;
            /// Identification number of the drive object being addressed
            driveObjectId : SINT := SINT#0;
            /// Hardware identifier of the hardware module (Drive/CU)
            hardwareId : UINT := UINT#0;
            /// Total amount of parameters in the current request
            parameterCount : INT := 0;
            /// Index of the parameter at which the error occurred (-1: no error)
            firstParameterError : INT := -1;
            /// Specific PROFIdrive error value (16#FF: no error)
            errorValue : USINT := USINT#16#FF;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
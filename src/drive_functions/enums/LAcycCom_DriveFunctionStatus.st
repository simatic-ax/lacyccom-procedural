NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Contains the status values for the drive functions
        DriveFunctionStatus : WORD (
            /// Execution finished without errors
            STATUS_EXECUTION_FINISHED := WORD#16#0000,
            /// At least one input (alarms or faults or SI messages) must be selected
            STATUS_FINISHED_NO_MSG_SELECTED := WORD#16#0001,
            /// No call of FB
            STATUS_NO_CALL := WORD#16#7000,
            /// First call of FB
            STATUS_FIRST_CALL := WORD#16#7001,
            /// Subsequent call of FB
            STATUS_SUBSEQUENT_CALL := WORD#16#7002,
            /// FB is currently allocating a request element
            STATUS_ALLOCATE := WORD#16#7100,
            /// FB is waiting until it has “speaking rights”
            STATUS_GET_RESOURCE := WORD#16#7101,
            /// FB is currently in processing
            STATUS_BUSY := WORD#16#7102,
            /// FB is releasing the allocated element
            STATUS_RELEASE := WORD#16#7103,
            /// Execute input set during silent operation mode
            WARN_EXECUTE := WORD#16#7200,
            /// Execute input set during processing
            WARN_EXECUTE_SET_DURING_PROCESSING := WORD#16#7201,
            /// Invalid count of parameters
            ERR_NO_OF_PARAMETERS := WORD#16#8001,
            /// FB is not called in OB1
            ERR_INVALID_PRIORITY_CLASS := WORD#16#8002,
            /// Request rejected
            ERR_REQUEST_REJECTED := WORD#16#8004,
            /// Request is already released
            ERR_RESOURCE_RELEASED := WORD#16#8005,
            /// Execute input set during processing (possible inconsistent data at output)
            ERR_AMBIGUOUS_FB_CALL := WORD#16#8006,
            /// Buffer index is invalid
            ERR_INVALID_BUF_INDEX := WORD#16#8201,
            /// Error in parameterizing the input powerUnit
            ERR_INVALID_PU_MODE := WORD#16#8204,
            /// Error in parameterizing the input encoder1
            ERR_INVALID_ENC1_MODE := WORD#16#8205,
            /// Error in parameterizing the input encoder2
            ERR_INVALID_ENC2_MODE := WORD#16#8206,
            /// Error in parameterizing the input encoder3
            ERR_INVALID_ENC3_MODE := WORD#16#8207,
            /// Drive Object ID is out of range (Drive Object ID < 0 for local access, 1..254 for global access is allowed)
            ERR_INVALID_DRIVE_OBJECT_ID := WORD#16#8208,
            /// The assigned buffer element is no longer available for the request
            ERR_COMMAND_TIMEOUT := WORD#16#8600,
            /// Counter for temporary errors reached the maximum during ReadRecord command
            ERR_READRECORD_TEMP_COUNTER := WORD#16#8601,
            /// Counter for temporary errors reached the maximum during WriteRecord command
            ERR_WRITERECORD_TEMP_COUNTER := WORD#16#8602,
            /// Error occurred during WriteRecord command
            ERR_WRITERECORD := WORD#16#8603,
            /// Error occurred during ReadRecord command
            ERR_READRECORD := WORD#16#8604,
            /// Reference number of the request does not match the response reference number
            ERR_REFERENCE_NO := WORD#16#8605,
            /// Invalid response from the drive object
            ERR_RESPONSE_ID := WORD#16#8606,
            /// The number of parameters received does not match the requested number of parameters
            ERR_PARAMETER_NO := WORD#16#8607,
            /// The drive object does not match the responded drive object
            ERR_DRIVE_OBJECT_NO := WORD#16#8608,
            /// The allocation time exceeded the configured value
            ERR_ALLOCATION_TIME := WORD#16#8609,
            /// The configured size of the response data buffer is too large for the record buffer used by ReadRecord
            ERR_MISSMATCH_READ_BUFFER_SIZE := WORD#16#8610,
            /// Error due to an undefined state
            ERR_UNDEFINED_STATE := WORD#16#8611,
            /// Error due to an undefined substate
            ERR_UNDEFINED_SUBSTATE := WORD#16#8612,
            /// Error during changing the drive object mode
            ERR_DO_MODE := WORD#16#8613,
            /// Error during changing the power unit mode
            ERR_PU_MODE := WORD#16#8614,
            /// Error during changing the encoder 1 mode
            ERR_ENC1_MODE := WORD#16#8615,
            /// Error during changing the encoder 2 mode
            ERR_ENC2_MODE := WORD#16#8616,
            /// Error during changing the encoder 3 mode
            ERR_ENC3_MODE := WORD#16#8617,
            /// Invalid drive object
            ERR_DO_ID := WORD#16#8618,
            /// Error during writing the parameter (see: errorValue)
            ERR_PARAMETER := WORD#16#8619,
            /// Hardware identifier does not exist or is not suitable for acyclic communication
            ERR_HW_ID := WORD#16#8620,
            /// Error occurred during ReadDriveParams command (alarms)
            ERR_READ_DRIVE_PARAMS_ALARMS := WORD#16#8621,
            /// Error occurred during ReadDriveParams command (faults)
            ERR_READ_DRIVE_PARAMS_FAULTS := WORD#16#8622,
            /// Error occurred during ReadDriveParams command (SI messages)
            ERR_READ_DRIVE_PARAMS_SI_MESSAGES := WORD#16#8623,
            /// Error occurred during ReadDriveParams command (reading parameter r2125)
            ERR_READ_DRIVE_PARAMS_ALARMS_GONE := WORD#16#8624,
            /// Error occurred during GetLocalDateTime command
            ERR_GET_LOCAL_DATE_TIME := WORD#16#8625,
            /// Error occurred during ReadHardwareIOAddress call
            ERR_READ_HARDWARE_IO_ADDRESS := WORD#16#8626,
            /// Missing confirmation after processing RamToRom in the drive (e.g. connection problem). See: diagnostics.subfunctionStatus
            ERR_MISSING_CONFIRMATION := WORD#16#8627,
            /// Ping for time synchronization is not set
            ERR_PING := WORD#16#8628
        ) := STATUS_NO_CALL;
    END_TYPE
END_NAMESPACE
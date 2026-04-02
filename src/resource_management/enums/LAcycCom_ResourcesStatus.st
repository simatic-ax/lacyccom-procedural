NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Contains the status values for the resource functions
        ResourcesStatus : WORD (
            /// Resource was successfully released
            STATUS_RESOURCE_RELEASED := WORD#16#0000,
            /// Execution finished without errors / Idle
            STATUS_NO_CALL := WORD#16#7000,
            /// First call of FB after enabling (Initialization)
            STATUS_FIRST_CALL := WORD#16#7001,
            /// Waiting for a resource (Asynchronous processing)
            STATUS_SUBSEQUENT_CALL := WORD#16#7002,
            /// Buffer is full; no more elements can be added
            STATUS_BUFFER_FULL := WORD#16#7003,
            /// Everything is okay and resource is assigned
            STATUS_RESOURCE_ASSIGNED := WORD#16#7004,
            
            /// Warning: Buffer lock time expired; lock is reset by FB
            WARN_BUFFER_LOCKED := WORD#16#7100,
            /// Warning: Internal system instruction 'ReadSlotFromHardwareID' returned an error
            WARN_WRONG_HARDWARE_ID := WORD#16#7101,
            
            /// Error: Request was rejected by FB while waiting in queue
            ERR_RESOURCE_REJECTED_WHILE_WAITING := WORD#16#8400,
            /// Error: Request was already released while waiting
            ERR_RESOURCE_RELEASED_WHILE_WAITING := WORD#16#8401,
            /// Error: Buffer is full, locked, or resource manager is inactive
            ERR_ALLOCATION := WORD#16#8600,
            /// Error: Buffer index is invalid
            ERR_INVALID_BUF_IDX := WORD#16#8601
        ) := STATUS_NO_CALL;
    END_TYPE
END_NAMESPACE
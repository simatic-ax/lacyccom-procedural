NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Defines the configuration used for LAcycCom_ResourceManager
        typeResourceManagerConfiguration : STRUCT
            /// Timeout for locking of complete request buffer. 
            /// If the application doesn't unlock, the Resource Manager takes control back.
            timeoutBufferLock : TIME := T#1S;
            /// Maximum waiting time of a request in the queue before it is forcefully removed.
            maxQueueTime : TIME := T#1M10S;
            /// Maximum time a communication resource (Hardware ID) can be assigned to a single request.
            maxAssignedTime : TIME := T#1M;
            /// Delay for releasing a resource after it was rejected (prevents rapid-fire retries).
            delayReleaseAfterReject : TIME := T#10S;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
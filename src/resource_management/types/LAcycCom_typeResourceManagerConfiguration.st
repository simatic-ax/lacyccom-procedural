NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Defines the configuration used for LAcycCom_ResourceManager
    LAcycCom_typeResourceManagerConfiguration : STRUCT
      timeoutBufferLock : TIME := T#1S;   /// Timeout for locking of complete request buffer, that means resource manager has no access
      maxQueueTime : TIME := T#1M10S;   /// Maximum waiting time of a request waiting in queue before releasing the element is enforced by resource manager
      maxAssignedTime : TIME := T#1M;   /// Maximum time a resource is assigned to a request
      delayReleaseAfterReject : TIME := T#10S;   /// Delay for releasing resource after it was rejected by resource manager
    END_STRUCT;
  END_TYPE
END_NAMESPACE
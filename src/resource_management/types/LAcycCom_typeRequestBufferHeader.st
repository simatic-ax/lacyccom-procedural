NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Defines common information of the request buffer used by various function blocks of LAcycCom to share and manage state of resources
    LAcycCom_typeRequestBufferHeader : STRUCT
    lockBuffer : BOOL := TRUE;   /// TRUE: Request buffer DB is locked by application
    nextFreeElement : INT := -1;   /// Next free request element in request buffer
    firstQueueElement : INT := -1;   /// Index of oldest element existing in request buffer
    numberOfRequests : INT := -1;   /// Number of existing requests in request buffer not released yet
    bufferLowerBound : DINT := 0;   /// Start index of buffer
    bufferUpperBound : DINT := 0;   /// End index of buffer
    activeRequests : ARRAY[0..LAcycCom_ResourcesConstants#ACTIVE_REQUESTS] OF LAcycCom_typeActiveRequest;   /// Currently enabled request elements
    END_STRUCT;
  END_TYPE

  TYPE
    /// Defines the information of an active request
    LAcycCom_typeActiveRequest : STRUCT
      bufferIndex : INT := -1;   /// Index of buffer element
      maxAssignedTime : TIME := T#1M;   /// Maximum time a resource is assigned to a request
    END_STRUCT;
  END_TYPE
END_NAMESPACE
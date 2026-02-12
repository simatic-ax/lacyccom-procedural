NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Contains diagnostics information about the resource manager
    LAcycCom_typeResourceManagerDiagnostics : STRUCT
      maxNoOfRequests : UINT;   /// Maximum number of requests in use in request buffer
      curRuntime : TIME;   /// Runtime of last call
      maxRuntime : TIME;   /// Maximum runtime of FB
    END_STRUCT;
  END_TYPE
END_NAMESPACE
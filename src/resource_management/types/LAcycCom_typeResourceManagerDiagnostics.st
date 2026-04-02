NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Contains diagnostics information about the resource manager
        typeResourceManagerDiagnostics : STRUCT
            /// Maximum number of requests that have been in the buffer simultaneously (High-water mark)
            maxNoOfRequests : UINT := UINT#0;
            /// Execution time of the last call of the Resource Manager FB
            curRuntime : TIME := T#0MS;
            /// Maximum execution time recorded for the Resource Manager FB (Peak load)
            maxRuntime : TIME := T#0MS;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
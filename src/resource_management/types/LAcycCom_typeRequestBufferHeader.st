NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Defines common information of the request buffer used by various function blocks of LAcycCom to share and manage state of resources
        typeRequestBufferHeader : STRUCT
            /// TRUE: Request buffer is locked by the application (prevents new processing)
            lockBuffer : BOOL := TRUE;
            /// Index of the next available free element in the request buffer
            nextFreeElement : INT := -1;
            /// Index of the oldest element currently waiting in the request buffer
            firstQueueElement : INT := -1;
            /// Total number of existing requests in the buffer that haven't been released
            numberOfRequests : INT := -1;
            /// The starting index of the buffer array (for boundary checking)
            bufferLowerBound : DINT := 0;
            /// The ending index of the buffer array (for boundary checking)
            bufferUpperBound : DINT := 0;
            /// Array tracking the elements currently being processed by the hardware
            activeRequests : ARRAY[0..ResourcesConstants#ACTIVE_REQUESTS] OF LAcycCom_typeActiveRequest;
        END_STRUCT;
    END_TYPE

    TYPE
        /// Defines the information of an active request
        LAcycCom_typeActiveRequest : STRUCT
            /// Index of buffer element
            bufferIndex : INT := -1;
            /// Maximum time a resource is assigned to a request
            maxAssignedTime : TIME := T#1M;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
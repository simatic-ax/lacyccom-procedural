NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Defines the buffer element used by various function blocks of LAcycCom to share and manage state of resources
        typeRequestBufferElement : STRUCT
            /// State of the request. 
            /// Bit 0: allocate new buffer element; 
            /// Bit 1: buffer element is assigned; 
            /// Bit 2: release buffer element; 
            /// Bit 3: request rejected
            state : BYTE := BYTE#16#00;
            /// Hardware identifier of the hardware module (Drive/CU)
            hardwareId : UINT := UINT#0;
            /// Index of the element in the queue before this element (-1 = None)
            queueElementPrevious : INT := -1;
            /// Index of the element in the queue after this element (-1 = None)
            queueElementNext : INT := -1;
            /// Time duration the element has been waiting in the queue
            queueTime : TIME := T#0MS;
        END_STRUCT;
    END_TYPE
END_NAMESPACE
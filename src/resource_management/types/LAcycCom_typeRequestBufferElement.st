NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Defines the buffer element used by various function blocks of LAcycCom to share and manage state of resources
    LAcycCom_typeRequestBufferElement : STRUCT
      state : BYTE := BYTE#16#00;   /// State of the request. Bit 0: allocate new buffer element; Bit 1: buffer element is assigned; Bit 2: release buffer element; Bit 3: request rejected
      hardwareId : UINT := UINT#0;   /// Hardware identifier of the hardware module
      queueElementPrevious : INT := -1;   /// Element in queue before this element
      queueElementNext: INT := -1;   /// Element in queue after this element
      queueTime : TIME := T#0MS;   /// Time duration element is in queue
    END_STRUCT;
  END_TYPE
END_NAMESPACE
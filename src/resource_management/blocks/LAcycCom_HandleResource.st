NAMESPACE Simatic.Ax.LAcycCom.Procedural
	///------------------------------------------------------------------------------------------
  /// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///------------------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Tested with: S7-1513-1 PN
	/// Engineering: SIMATIC AX
	/// Restrictions: ---
	/// Requirements: S7-1200 / S7-1500
	/// Functionality: Allocate and release an element in the request buffer.
	///------------------------------------------------------------------------------------------
  FUNCTION_BLOCK LAcycCom_HandleResource
    {S7.Extern = ReadWrite}
    VAR_INPUT
      requestResource : BOOL;   /// TRUE: A new resource is requested; FALSE: Resource is not needed any more
      hardwareId : UINT;   /// Hardware identifier of the hardware module
      maxAssignedTime : TIME := T#1M;   /// Maximum time a resource is assigned to a request
    END_VAR

    {S7.Extern = ReadOnly}
    VAR_OUTPUT
      error: BOOL;   /// TRUE: Rising edge informs that an error occurred during the execution of the FB
      status: LAcycCom_ResourcesStatus;   /// Status identifier
      waitingForResource: BOOL;   /// TRUE: FB is waiting for a resource
      resourceAssigned: BOOL;   /// TRUE: Resource can be used
      resourceReleased: BOOL;   /// TRUE: Resource was released
      usedHardwareId: UINT;   /// Hardware identifier of the assigned buffer element
    END_VAR

    VAR_IN_OUT
      requestBufferHeader : LAcycCom_typeRequestBufferHeader;   /// Interface for header of request buffer
      requestBuffer : ARRAY[*] OF LAcycCom_typeRequestBufferElement;   /// Interface for request buffer
    END_VAR

    VAR
      _firstCycle : BOOL := TRUE;   /// Variable that indicates the first cycle
      _bufferIndex : INT := -1;   /// Index of buffer element
    END_VAR

    VAR_TEMP
      tempIndex : DINT;   // Temporary loop index variable
      tempLastQueueElement : INT;   // Last element in queue
      tempCurReqState : BYTE;   // Current request state
      tempRequestBufferElement : LAcycCom_typeRequestBufferElement;   // Temporary buffer element
    END_VAR

    VAR CONSTANT
      ALL_ELEMENTS_OCCUPIED : INT := -1;   // All buffer elements are occupied
    END_VAR
    
    IF requestBufferHeader.lockBuffer = TRUE THEN
      RETURN;
    END_IF;
        
    //=============================================================================
    // Request resource
    //=============================================================================
    IF (requestResource = TRUE) AND (_bufferIndex < 0) THEN
      error := FALSE;
      _firstCycle := TRUE;
     
      // Allocation of a request element
      IF (requestBufferHeader.lockBuffer = FALSE) AND (requestBufferHeader.nextFreeElement >= requestBufferHeader.bufferLowerBound) AND (requestBufferHeader.nextFreeElement <= requestBufferHeader.bufferUpperBound) THEN
        requestBufferHeader.lockBuffer := TRUE;
        _bufferIndex := requestBufferHeader.nextFreeElement;
        
        tempRequestBufferElement := requestBuffer[_bufferIndex];
       
        tempRequestBufferElement.state := BYTE#16#00;
        tempRequestBufferElement.state.%X0 := TRUE;
        tempRequestBufferElement.hardwareId := hardwareId;
        tempRequestBufferElement.queueElementNext := -1;
        
        requestBuffer[_bufferIndex] := tempRequestBufferElement;
               
        usedHardwareId := hardwareId;
        
        // Build up queue
        IF (requestBufferHeader.firstQueueElement >= 0) THEN
          // Find last queue element 
          tempIndex := requestBufferHeader.firstQueueElement;
          WHILE (tempIndex >= 0) DO
            tempLastQueueElement := TO_INT(tempIndex);
            
            tempRequestBufferElement := requestBuffer[tempIndex];

            tempIndex := tempRequestBufferElement.queueElementNext;
          END_WHILE;
          
          // insert into list after last element
          tempRequestBufferElement.queueElementNext := _bufferIndex;
          
          requestBuffer[tempLastQueueElement] := tempRequestBufferElement;
          
          tempRequestBufferElement := requestBuffer[_bufferIndex];
          
          tempRequestBufferElement.queueElementPrevious := tempLastQueueElement;
          
          requestBuffer[_bufferIndex] := tempRequestBufferElement;         
        ELSE
          // Element is first element in queue
          requestBufferHeader.firstQueueElement := _bufferIndex;
          
          tempRequestBufferElement := requestBuffer[_bufferIndex];
          
          tempRequestBufferElement.queueElementPrevious := -1;

          requestBuffer[_bufferIndex] := tempRequestBufferElement;
        END_IF;
        
        status := LAcycCom_ResourcesStatus#STATUS_SUBSEQUENT_CALL;
        
        // Searching for the next free buffer element
        FOR tempIndex := requestBufferHeader.bufferLowerBound TO requestBufferHeader.bufferUpperBound DO
          tempRequestBufferElement := requestBuffer[tempIndex];
          
          IF (tempRequestBufferElement.state.%X0 = FALSE) THEN
            requestBufferHeader.nextFreeElement := TO_INT(tempIndex);
            EXIT;
          END_IF;
          
          // All buffer elements are occupied
          IF tempIndex = requestBufferHeader.bufferUpperBound THEN
            requestBufferHeader.nextFreeElement := ALL_ELEMENTS_OCCUPIED;
          END_IF;
        END_FOR;
        
        waitingForResource := TRUE;
        resourceAssigned := FALSE;
        requestBufferHeader.lockBuffer := FALSE;
        
        // Waiting until lockbit is reset and a buffer element is available
      ELSE
        status := LAcycCom_ResourcesStatus#ERR_ALLOCATION;
        error := TRUE;
      END_IF;
      
      //=============================================================================
      // Check resource
      //=============================================================================
    ELSIF (requestResource = TRUE) THEN
      // Check buffer index for correctness
      IF (_bufferIndex < 0) OR (_bufferIndex > requestBufferHeader.bufferUpperBound) THEN
        status := LAcycCom_ResourcesStatus#ERR_INVALID_BUF_IDX;
        error := TRUE;
        waitingForResource := FALSE;
        resourceAssigned := FALSE;
        RETURN; // V1.1.3
      ELSE
        
        tempRequestBufferElement := requestBuffer[_bufferIndex];
        
        tempCurReqState := tempRequestBufferElement.state;
        usedHardwareId := tempRequestBufferElement.hardwareId;
        
        IF (tempCurReqState.%X0 = FALSE) OR
          (tempCurReqState.%X3 = TRUE)
        THEN
          // Request was rejected by buffer manager
          resourceAssigned := FALSE;
          waitingForResource := FALSE;
          error := TRUE;
          status := LAcycCom_ResourcesStatus#ERR_RESOURCE_REJECTED_WHILE_WAITING;
          RETURN; // V1.1.3
          
        ELSIF (tempCurReqState.%X2 = TRUE) THEN
          // Request already released
          waitingForResource := FALSE;
          resourceAssigned := FALSE;
          error := TRUE;
          status := LAcycCom_ResourcesStatus#ERR_RESOURCE_RELEASED_WHILE_WAITING;
          RETURN; // V1.1.3
          
        ELSIF (tempCurReqState.%X1 = TRUE) THEN
          // Element is enabled
          IF (_firstCycle = TRUE) THEN
            IF (requestBufferHeader.lockBuffer = FALSE) THEN // V1.1.2
              requestBufferHeader.lockBuffer := TRUE;
              
              FOR tempIndex := requestBufferHeader.bufferLowerBound TO requestBufferHeader.bufferUpperBound DO
                IF (requestBufferHeader.activeRequests[tempIndex].bufferIndex = _bufferIndex) THEN
                  // Choose global maxAssignedTime
                  IF (requestBufferHeader.activeRequests[tempIndex].maxAssignedTime >= maxAssignedTime) THEN
                    ; // do nothing
                    
                    // Choose maxAssignedTime  
                  ELSE
                    requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := maxAssignedTime;
                  END_IF;
                  _firstCycle := FALSE;
                  EXIT;
                END_IF;
              END_FOR;
              
              requestBufferHeader.lockBuffer := FALSE; // V1.1.2
              waitingForResource := FALSE;
              resourceAssigned := TRUE;
              status := LAcycCom_ResourcesStatus#STATUS_RESOURCE_ASSIGNED;
            END_IF;
          END_IF;
          
        ELSE
          // Element not enabled yet
          waitingForResource := TRUE;
          resourceAssigned := FALSE;
          status := LAcycCom_ResourcesStatus#STATUS_SUBSEQUENT_CALL;
        END_IF;
      END_IF;
      
      //=============================================================================
      // Resource can be released
      //=============================================================================
    ELSIF (requestResource = FALSE) AND (_bufferIndex >= 0) THEN
      // Check buffer index for correctness
      IF (_bufferIndex < 0) OR (_bufferIndex > requestBufferHeader.bufferUpperBound) THEN
        status := LAcycCom_ResourcesStatus#ERR_INVALID_BUF_IDX;
      ELSE
        _firstCycle := TRUE; // V1.1.2
        IF requestBufferHeader.lockBuffer = FALSE THEN // V1.1.2
          requestBufferHeader.lockBuffer := TRUE;
          
          tempRequestBufferElement := requestBuffer[_bufferIndex];
                  
          IF (tempRequestBufferElement.state.%X0 = TRUE) THEN
            tempRequestBufferElement.state.%X2 := TRUE;
            
            requestBuffer[_bufferIndex] := tempRequestBufferElement;
          END_IF;

          _bufferIndex := -1;
          usedHardwareId := UINT#0;
          resourceReleased := TRUE;
          waitingForResource := FALSE;
          resourceAssigned := FALSE;
          status := LAcycCom_ResourcesStatus#STATUS_RESOURCE_RELEASED;
          _firstCycle := FALSE;
          
          requestBufferHeader.lockBuffer := FALSE;
        END_IF;
      END_IF;
    ELSE
      resourceReleased := FALSE; // No resource requested yet
      error := FALSE;
      status := LAcycCom_ResourcesStatus#STATUS_NO_CALL;
    END_IF;
  END_FUNCTION_BLOCK
END_NAMESPACE
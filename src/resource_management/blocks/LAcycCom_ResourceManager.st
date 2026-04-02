USING System.Timer;
USING Siemens.Simatic.Hardware.Utilities;
USING Siemens.Simatic.Diagnostics;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE INTERNAL
        typeCurrentRequestState : STRUCT
            allocated : BOOL;
            assigned : BOOL;
            release : BOOL;
            rejected : BOOL;
        END_STRUCT;
    END_TYPE

    TYPE INTERNAL
        typeResourceAddInfo : STRUCT
            IOSystem : INT;
            station : INT;
        END_STRUCT;
    END_TYPE

	///==========================================================================================
    /// SIEMENS AG
	/// (c)Copyright 2026 All Rights Reserved
	///------------------------------------------------------------------------------------------
	/// Library: LAcycCom
	/// Engineering: SIMATIC AX
	/// Restrictions: -
	/// Requirements: S7-1200 / S7-1500
	/// Functionality: Central buffer management for arbitration of DPV1 services
	///==========================================================================================
    FUNCTION_BLOCK ResourceManager
        {S7.Extern = ReadWrite}
        VAR_INPUT
            /// TRUE: Enable functionality of FB
            enable : BOOL;
            /// Configuration structure of ResourceManager FB
            config : typeResourceManagerConfiguration;
        END_VAR

        {S7.Extern = ReadOnly}
        VAR_OUTPUT
            /// TRUE: Valid set of outputs available at the FB
            valid : BOOL;
            /// TRUE: FB is working and new output values can be expected
            busy : BOOL;
            /// TRUE: Rising edge informs that an error occurred during the execution of the FB
            error : BOOL;
            /// Current status of FB
            status : ResourcesStatus;
            /// Diagnostics information of FB
            diagnostics : typeResourceManagerDiagnostics;
        END_VAR

        VAR_IN_OUT
            /// Interface for header of request buffer
            requestBufferHeader : typeRequestBufferHeader;
            /// Interface for request buffer
            requestBuffer : ARRAY[*] OF typeRequestBufferElement;
        END_VAR

        VAR
            /// Additional resource information
            _resourceAddInfo : ARRAY[0..ResourcesConstants#ACTIVE_REQUESTS] OF typeResourceAddInfo;
            /// Identification and maintanance data
            _IM0Data : IM0Data;
            /// Store for maintenance data
            _MData : STRING;
            /// Number of used resources
            _noOfUsedResources : INT := 0;
            /// Upper limit of resources for acyclic communication
            _upperLimResources: INT := 0;
            /// Error occurred that can only be solved by user; rising edge at enable input is necessary
            _errorUserCleared : BOOL := FALSE;
            /// Error occurred that can be acknowledged by FB
            _errorAutoCleared: BOOL := FALSE;
            /// Old value of enable for edge detection
            _enableOld : BOOL := FALSE;
            /// FB is disabled and currently finishing all requests
            _disabling : BOOL := FALSE;
            /// Request buffer lower bound
            _requestBufferLowerBound : DINT := DINT#0;
            /// Request buffer upper bound 
            _requestBufferUpperBound : DINT := DINT#0;
            /// Reading identification and maintanance data
            _instGetIMData : GetIMData;
            /// Watchdog timer for request buffer lock bit
            _instBufferLockWatchdog : OnDelay;
            /// Timer for runtime measurement
            _instRuntime : OnDelay;
            /// Timer for detecting cycle time
            _instCycleTime : OnDelay;
        END_VAR

        VAR_TEMP
            // Temporary request buffer element
            tempRequestBufferElement : typeRequestBufferElement;
            // Temporaray depending request buffer element
            tempRequestBufferDepending : typeRequestBufferElement;
            // Current Geo Address information
            tempCurGeoAddr : GeoAddr;
            tempCurReqState : typeCurrentRequestState;
            // Current runtime for FB
            tempCurRuntime : TIME;
            // Current cycle time
            tempCycleTime : TIME;
            // Current queue time
            tempCurQueueTime : TIME;
            // Number of requests
            tempNoOfRequests : INT;
            // First element in current queue
            tempFirstQueueElement : INT;
            // Index for loop handling
            tempIndex : DINT;
            // Number of free resources
            tempNoOfFreeResources : INT;
            // Actual index of buffer element
            tempActBufferIndex : INT;
            // Queue element before current element
            tempQueueElementPrevious : INT;
            // Queue element after current element
            tempQueueElementNext : INT;
            // Return value of system functions
            tempRetVal : WORD;
            // Temporary byte variable for slice command
            tempByte : BYTE;
            // Station is already processing with acyclic communication
            tempStationInUse : BOOL;
            // Temporary count of elements (request buffer)
            tempCountOfElements : INT;
        END_VAR

        VAR CONSTANT 
            // Maximum time for runtime timer
            TIME_RUNTIME_TIMER : TIME := T#1D;
            // Maximum number of resources for acyclic communication when using a 1200 CPU (Firmware V4.x)
            MAX_NO_OF_RESOURCES_1200_V4 : INT := 4;
            // Maximum number of resources for acyclic communication when using a 1500 CPU (Firmware V1.x)
            MAX_NO_OF_RESOURCES_1500_V1 : INT := 10;
            // Maximum number of resources for acyclic communication when using a 1500 CPU (Firmware V2.x)
            MAX_NO_OF_RESOURCES_1500_V2 : INT := 20;
        END_VAR

        //Check if FB is been disabled
        IF NOT enable AND _enableOld THEN
            _requestBufferLowerBound := DINT#0;
            _requestBufferUpperBound := DINT#0;

            //Check if no request is executed at the moment
            IF (_noOfUsedResources <= 0)
                OR _errorUserCleared
            THEN
                requestBufferHeader.lockBuffer := TRUE;
                requestBufferHeader.numberOfRequests := -1;
                requestBufferHeader.nextFreeElement := -1;
                requestBufferHeader.bufferLowerBound := _requestBufferLowerBound;
                requestBufferHeader.bufferUpperBound := _requestBufferUpperBound;
                
                FOR tempIndex := 0 TO ResourcesConstants#ACTIVE_REQUESTS DO
                    requestBufferHeader.activeRequests[tempIndex].bufferIndex := -1;
                    requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := config.maxAssignedTime;
                    _resourceAddInfo[tempIndex].IOSystem := -1;
                    _resourceAddInfo[tempIndex].station := -1;
                END_FOR;
                
                //Error outputs are reset with falling edge of enable input
                _errorUserCleared := FALSE;
                _errorAutoCleared := FALSE;
                _disabling := FALSE;
                error := FALSE;
                status := ResourcesStatus#STATUS_NO_CALL;
                
                //Enable and busy are reset with falling edge of enable input
                valid := FALSE;
                busy := FALSE;
                
                //Set old value of enable for edge detection and end execution
                _enableOld := enable;
                RETURN;
                
            ELSE
                // Wait for requests to be finished
                _disabling := TRUE;
            END_IF;
        
        //Check if FB is enabled
        ELSIF (enable AND NOT _enableOld AND NOT _disabling) THEN
            _requestBufferLowerBound := LOWER_BOUND(requestBuffer, 1);
            _requestBufferUpperBound := UPPER_BOUND(requestBuffer, 1);

            requestBufferHeader.lockBuffer := TRUE;
            requestBufferHeader.numberOfRequests := 0;
            requestBufferHeader.nextFreeElement := TO_INT(_requestBufferLowerBound);
            requestBufferHeader.firstQueueElement := -1;

            // write size of buffer to header
            requestBufferHeader.bufferLowerBound := _requestBufferLowerBound;
            requestBufferHeader.bufferUpperBound := _requestBufferUpperBound;
            
            _instRuntime(signal := FALSE, duration := TIME_RUNTIME_TIMER);
            _instCycleTime(signal := FALSE, duration := TIME_RUNTIME_TIMER);
            _instBufferLockWatchdog(signal := FALSE, duration := TIME_RUNTIME_TIMER);
            
            diagnostics.maxNoOfRequests := UINT#0;
            diagnostics.maxRuntime := T#0s;
            
            FOR tempIndex := _requestBufferLowerBound TO _requestBufferUpperBound DO	    
                tempRequestBufferElement := requestBuffer[tempIndex];

                tempRequestBufferElement.state := BYTE#16#00;
                tempRequestBufferElement.hardwareId := UINT#0;
                tempRequestBufferElement.queueElementNext := -1;
                tempRequestBufferElement.queueElementPrevious := -1;
                tempRequestBufferElement.queueTime := T#0s;

                requestBuffer[tempIndex] := tempRequestBufferElement;
            END_FOR;
        
            FOR tempIndex := 0 TO ResourcesConstants#ACTIVE_REQUESTS DO
                requestBufferHeader.activeRequests[tempIndex].bufferIndex := -1;
                requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := config.maxAssignedTime;
                _resourceAddInfo[tempIndex].IOSystem := -1;
                _resourceAddInfo[tempIndex].station := -1;
            END_FOR;
            
            REPEAT
                // Set maximum number of resources from I&M Data
                _instGetIMData(hardwareID := UINT#50, imType := UINT#0, iData := _IM0Data, mData := _MData); 
            UNTIL (_instGetIMData.DONE) OR (_instGetIMData.ERROR) END_REPEAT;
        
            IF _instGetIMData.DONE THEN
                IF (_IM0Data.OrderID[6] = '2') THEN
                    // Order ID of 1200 CPU detected
                    _upperLimResources := MAX_NO_OF_RESOURCES_1200_V4 - 1;
                    
                ELSE
                    // If no 1200 CPU it have to be a 1500 CPU or a 1500 Software controller
                    IF (_IM0Data.SoftwareRevision.Functional >= 2) THEN
                        _upperLimResources := MAX_NO_OF_RESOURCES_1500_V2 - 1; // Firmware V2.x
                        
                    ELSE
                        _upperLimResources := MAX_NO_OF_RESOURCES_1500_V1 - 1; // Firmware V1.x
                    END_IF;
                END_IF;
            ELSE
                // If no I&M data coul be read, use the lower number of resources
                _upperLimResources := MAX_NO_OF_RESOURCES_1200_V4 - 1;
            END_IF;
            
            requestBufferHeader.lockBuffer := FALSE;
        
            busy := TRUE; //Busy is set at rising edge of enable input
            status := ResourcesStatus#STATUS_FIRST_CALL; //Set status for first call
            _enableOld := enable; //Set old value of enable for edge detection and end execution
            RETURN;
            
        //Check if user cleared error in FB occurred
        ELSIF _errorUserCleared THEN
            busy := FALSE;
            _enableOld := enable;
            //No set of status necessary, because status already set when error occurred
            RETURN;
        
        //Check if function block is disabled
        ELSIF NOT enable AND NOT _disabling THEN
            busy := FALSE;
            status := ResourcesStatus#STATUS_NO_CALL;
            _enableOld := enable;
            RETURN;
        
        ELSE
            // Reset automatically cleared errors
            _errorAutoCleared := FALSE;
            
            //Detect edge for disabling
            _enableOld := enable;
        END_IF;
        //----------------------------------------------------------------------------------------------
        
        // Get current runtime
        _instRuntime(signal := TRUE, duration := TIME_RUNTIME_TIMER);
        
        // Cycle time measurement
        _instCycleTime(signal := TRUE, duration := TIME_RUNTIME_TIMER);
        
        tempCycleTime := TO_TIME(_instCycleTime.elapsedTime);
        
        _instRuntime(signal := FALSE, duration := TIME_RUNTIME_TIMER);
        _instCycleTime(signal := FALSE, duration := TIME_RUNTIME_TIMER);
        
        
        // Watchdog for lock of complete buffer DB
        _instBufferLockWatchdog(signal := requestBufferHeader.lockBuffer, duration := config.timeoutBufferLock);
        
        // Check if buffer was locked too long
        IF _instBufferLockWatchdog.output THEN
            _errorAutoCleared := TRUE;
            requestBufferHeader.lockBuffer := FALSE;
            status := ResourcesStatus#WARN_BUFFER_LOCKED;
            
        ELSIF requestBufferHeader.lockBuffer THEN
            ; // Do nothing until buffer is unlocked
            
        ELSE
            requestBufferHeader.lockBuffer := TRUE; // Lock Buffer to change elements via Variant
            
            //----------------------------------------------------------------------------------------------
            // Release elements blocking resources
            //----------------------------------------------------------------------------------------------  
            _noOfUsedResources := 0;
            tempFirstQueueElement := requestBufferHeader.firstQueueElement;
            
            // Check and release buffer items
            FOR tempIndex := 0 TO ResourcesConstants#ACTIVE_REQUESTS DO
                tempActBufferIndex := requestBufferHeader.activeRequests[tempIndex].bufferIndex;
                // Check if current index is used for a resource
                IF (tempActBufferIndex >= 0) THEN
                    tempRequestBufferElement := requestBuffer[tempActBufferIndex];
                    
                    tempByte := tempRequestBufferElement.state;
                    tempCurReqState.allocated := tempByte.%X0;
                    tempCurReqState.assigned := tempByte.%X1;
                    tempCurReqState.release := tempByte.%X2;
                    tempCurReqState.rejected := tempByte.%X3;
                
                    // Check if resource can be released
                    IF tempCurReqState.release THEN
                        tempQueueElementPrevious := tempRequestBufferElement.queueElementPrevious;
                        tempQueueElementNext := tempRequestBufferElement.queueElementNext;
                        
                        IF (tempQueueElementPrevious = -1) AND
                            (tempQueueElementNext = -1)
                        THEN
                            // Only element in queue; Reset pointer for first element
                            tempFirstQueueElement := -1;
                            requestBufferHeader.firstQueueElement := -1;
                            
                        ELSIF (tempQueueElementPrevious = -1) THEN
                            // Element was first element in queue
                            tempRequestBufferDepending := requestBuffer[tempQueueElementNext];
                            
                            tempRequestBufferDepending.queueElementPrevious := -1;

                            requestBuffer[tempQueueElementNext] := tempRequestBufferDepending;
                            
                            
                            requestBufferHeader.firstQueueElement := tempQueueElementNext;
                            tempFirstQueueElement := tempQueueElementNext;
                            
                        ELSIF (tempQueueElementNext = -1) THEN
                            // Element was last element in queue
                            tempRequestBufferDepending := requestBuffer[tempQueueElementPrevious];

                            tempRequestBufferDepending.queueElementNext := -1;

                            requestBuffer[tempQueueElementPrevious] := tempRequestBufferDepending;	                  
                        ELSE
                            // Current element has a previous and next element
                            tempRequestBufferDepending := requestBuffer[tempQueueElementNext];

                            tempRequestBufferDepending.queueElementPrevious := tempQueueElementPrevious;

                            requestBuffer[tempQueueElementNext] := tempRequestBufferDepending;
                                        

                            tempRequestBufferDepending := requestBuffer[tempQueueElementPrevious];

                            tempRequestBufferDepending.queueElementNext := tempQueueElementNext;

                            requestBuffer[tempQueueElementPrevious] := tempRequestBufferDepending;
                        END_IF;
                            
                        tempRequestBufferElement.state := BYTE#16#00;
                        tempRequestBufferElement.hardwareId := UINT#0;
                        tempRequestBufferElement.queueElementPrevious := -1;
                        tempRequestBufferElement.queueElementNext := -1;
                        tempRequestBufferElement.queueTime := T#0s;
                        
                        requestBuffer[tempActBufferIndex] := tempRequestBufferElement;
                        
                        requestBufferHeader.activeRequests[tempIndex].bufferIndex := -1;
                        requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := config.maxAssignedTime;
                        _resourceAddInfo[tempIndex].IOSystem := -1;
                        _resourceAddInfo[tempIndex].station := -1;
                    
                        // Check if buffer was full when last element tries to allocate
                        IF (requestBufferHeader.nextFreeElement < 0) THEN
                            // Set actual write index to current released element
                            requestBufferHeader.nextFreeElement := tempActBufferIndex;
                        END_IF;
                        
                    ELSE
                        _noOfUsedResources := _noOfUsedResources + 1;
                    END_IF; // tempCurReqState.release
                
                ELSE
                    ; // Check next resource
                END_IF; // (tempActBufferIndex >= 0)
            END_FOR;
        
            tempNoOfFreeResources := _upperLimResources - _noOfUsedResources; // Calculate free resources
        
            //----------------------------------------------------------------------------------------------
            // Release other elements and assign resources to elements
            //----------------------------------------------------------------------------------------------  
            tempActBufferIndex := tempFirstQueueElement;
            tempNoOfRequests := 0;
            
            WHILE (tempActBufferIndex >= 0) DO
                tempRequestBufferElement := requestBuffer[tempActBufferIndex];
                
                tempQueueElementNext := tempRequestBufferElement.queueElementNext; // Set next element
                tempByte := tempRequestBufferElement.state;
                tempCurReqState.allocated := tempByte.%X0;
                tempCurReqState.assigned := tempByte.%X1;
                tempCurReqState.release := tempByte.%X2;
                tempCurReqState.rejected := tempByte.%X3;
                
                // Check if resource can be released
                IF tempCurReqState.release THEN
                tempQueueElementPrevious := tempRequestBufferElement.queueElementPrevious;
                
                IF (tempQueueElementPrevious = -1) AND
                    (tempQueueElementNext = -1)
                THEN
                    // Only element in queue; Reset pointer for first element
                    tempFirstQueueElement := -1;
                    requestBufferHeader.firstQueueElement := -1;
                    
                ELSIF (tempQueueElementPrevious = -1) THEN
                    // Element was first element in queue
                    tempRequestBufferDepending := requestBuffer[tempQueueElementNext];
                    
                    tempRequestBufferDepending.queueElementPrevious := -1;
                    
                    requestBuffer[tempQueueElementNext] := tempRequestBufferDepending;

                    
                    tempFirstQueueElement := tempQueueElementNext;
                    requestBufferHeader.firstQueueElement := tempQueueElementNext;
                    
                ELSIF (tempQueueElementNext = -1) THEN
                    // Element was last element in queue        
                    tempRequestBufferDepending := requestBuffer[tempQueueElementPrevious];

                    tempRequestBufferDepending.queueElementNext := -1;
                    
                    requestBuffer[tempQueueElementPrevious] := tempRequestBufferDepending;        
                ELSE
                    tempRequestBufferDepending := requestBuffer[tempQueueElementNext];
                    
                    tempRequestBufferDepending.queueElementPrevious := tempQueueElementPrevious;
                    
                    requestBuffer[tempQueueElementNext] := tempRequestBufferDepending;

                    
                    tempRequestBufferDepending := requestBuffer[tempQueueElementPrevious];
                            
                    tempRequestBufferDepending.queueElementNext := tempQueueElementNext;
                    
                    requestBuffer[tempQueueElementPrevious] := tempRequestBufferDepending;
                END_IF;
                
                tempRequestBufferElement.state := BYTE#16#00;
                tempRequestBufferElement.hardwareId := UINT#0;
                tempRequestBufferElement.queueElementPrevious := -1;
                tempRequestBufferElement.queueElementNext := -1;
                tempRequestBufferElement.queueTime := T#0s;
                
                tempRequestBufferElement := requestBuffer[tempActBufferIndex];
                
                FOR tempIndex := 0 TO ResourcesConstants#ACTIVE_REQUESTS DO // V1.1.2
                    IF requestBufferHeader.activeRequests[tempIndex].bufferIndex = tempActBufferIndex THEN
                    requestBufferHeader.activeRequests[tempIndex].bufferIndex := -1;
                    requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := config.maxAssignedTime;
                    
                    _resourceAddInfo[tempIndex].IOSystem := -1;
                    _resourceAddInfo[tempIndex].station := -1;
                    EXIT;
                    END_IF;
                END_FOR;
                
                // Check if buffer was full when last element tries to allocate
                IF (requestBufferHeader.nextFreeElement < 0) THEN
                    // Set actual write index to current released element
                    requestBufferHeader.nextFreeElement := tempActBufferIndex;
                END_IF;
                
                ELSE // NOT  tempCurReqState.release 
                // Count elements and go to next element
                tempNoOfRequests := tempNoOfRequests + 1;
                
                // Calculate queue time of current request
                tempRequestBufferElement := requestBuffer[tempActBufferIndex];   
                
                tempCurQueueTime := tempCycleTime + tempRequestBufferElement.queueTime;
                tempRequestBufferElement.queueTime := tempCurQueueTime;
                
                // Check if resource was already assigned
                IF tempCurReqState.assigned THEN
                    
                    FOR tempIndex := 0 TO _upperLimResources DO
                    IF (requestBufferHeader.activeRequests[tempIndex].bufferIndex = tempActBufferIndex) THEN
                        // Choose maxAssignedTime of resource
                        IF (requestBufferHeader.activeRequests[tempIndex].maxAssignedTime >= config.maxAssignedTime) THEN
                        ; // do nothing
                        
                        // Choose global maxAssignedTime
                        ELSE
                        requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := config.maxAssignedTime;
                        END_IF;
                        EXIT;
                    END_IF;
                    END_FOR;
                    
                    IF (tempCurQueueTime < requestBufferHeader.activeRequests[tempIndex].maxAssignedTime) THEN
                    ; // Everything okay
                    ELSIF (tempCurQueueTime < (requestBufferHeader.activeRequests[tempIndex].maxAssignedTime + config.delayReleaseAfterReject)) THEN
                    // Current element is over queue time
                    tempRequestBufferElement.state.%X3 := TRUE; // Request rejected
                    ELSE
                    // Current element is over queue time and is released in next cycle
                    tempRequestBufferElement.state.%X2 := TRUE; // Request release
                    END_IF;
                    
                    // Check if block is disabled and reject all new requests 
                ELSIF (_disabling) THEN
                    // Current element is rejected cause function block is disabled          
                    tempRequestBufferElement.state.%X3 := TRUE; // Request rejected
                    
                    // If current time is over the delay, release the request asap
                    IF (tempCurQueueTime > config.delayReleaseAfterReject) THEN
                    tempRequestBufferElement.state.%X2 := TRUE; // Request release
                    END_IF;
                    
                ELSE
                    tempRetVal := ReadSlotFromHardwareID(hardwareID := tempRequestBufferElement.hardwareId, geoAddr := tempCurGeoAddr);
                    
                    // Check if everything is okay
                    IF tempRetVal <> WORD#16#0 THEN
                    tempRequestBufferElement.state.%X3 := TRUE; // Request rejected because of error in system function
                    _errorAutoCleared := TRUE;
                    status := ResourcesStatus#WARN_WRONG_HARDWARE_ID;
                    ELSE
                    ; // Everything okay
                    END_IF;
                    
                    // Check if hardware is already in use
                    tempStationInUse := FALSE;
                    
                    FOR tempIndex := 0 TO _upperLimResources DO
                    // Check if station is already in use by a request
                    IF (_resourceAddInfo[tempIndex].IOSystem = TO_INT(tempCurGeoAddr.IOSYSTEM)) AND
                        (_resourceAddInfo[tempIndex].station = TO_INT(tempCurGeoAddr.STATION))
                    THEN
                        tempStationInUse := TRUE;
                        EXIT;
                    ELSE
                        ; // Check next element
                    END_IF;
                    END_FOR;
                    
                    // Check if station can be enabled
                    IF NOT tempStationInUse THEN
                    // Search for free resource
                    FOR tempIndex := 0 TO ResourcesConstants#ACTIVE_REQUESTS DO
                        // Check for free slot
                        IF (_resourceAddInfo[tempIndex].IOSystem = -1) AND
                        (_resourceAddInfo[tempIndex].station = -1)
                        THEN
                        // Set information and enable request
                        _resourceAddInfo[tempIndex].IOSystem := TO_INT(tempCurGeoAddr.IOSYSTEM);
                        _resourceAddInfo[tempIndex].station := TO_INT(tempCurGeoAddr.STATION);
                        
                        tempRequestBufferElement.queueTime := T#0s;
                        tempRequestBufferElement.state.%X1 := TRUE; // Resource assigned to request
                        
                        requestBufferHeader.activeRequests[tempIndex].bufferIndex := tempActBufferIndex;
                        _noOfUsedResources := _noOfUsedResources + 1;
                        tempNoOfFreeResources := tempNoOfFreeResources - 1;
                        EXIT;
                        ELSE
                        ; // Check next element
                        END_IF;
                    END_FOR;
                    
                    ELSE
                    // Current request can not be added, because other request is active on station
                    IF (tempCurQueueTime < config.maxQueueTime) THEN
                        ; // Everything okay
                        
                    ELSIF (tempCurQueueTime < (config.maxQueueTime + config.delayReleaseAfterReject)) THEN
                        // Current element is over queue time
                        tempRequestBufferElement.state.%X3 := TRUE; // Request rejected
                        
                    ELSE
                        // Current element is over queue time and is released in next cycle
                        tempRequestBufferElement.state.%X2 := TRUE; // Request released
                    END_IF;
                    END_IF; // tempCurReqState.assigned
                END_IF; // NOT tempStationInUse
                END_IF; //  tempCurReqState.release 
                
                requestBuffer[tempActBufferIndex] := tempRequestBufferElement;

                tempActBufferIndex := tempQueueElementNext; // Switch to next buffer element
            END_WHILE;
        
            requestBufferHeader.lockBuffer := FALSE; // Release Buffer to change elements via Variant
            
            // Check if block can be disabled
            IF (_disabling AND (tempNoOfRequests = 0)) THEN
                _disabling := FALSE; // Reset disabling bit
                
                // Initialize buffer and FB
                requestBufferHeader.lockBuffer := TRUE;
                requestBufferHeader.numberOfRequests := -1;
                requestBufferHeader.nextFreeElement := -1;
                
                FOR tempIndex := 0 TO ResourcesConstants#ACTIVE_REQUESTS DO
                    requestBufferHeader.activeRequests[tempIndex].bufferIndex := -1;
                    requestBufferHeader.activeRequests[tempIndex].maxAssignedTime := config.maxAssignedTime;
                    _resourceAddInfo[tempIndex].IOSystem := -1;
                    _resourceAddInfo[tempIndex].station := -1;
                END_FOR;
                
                //Error outputs are reset with falling edge of enable input
                _errorUserCleared := FALSE;
                _errorAutoCleared := FALSE;
                
                error := FALSE;
                status := ResourcesStatus#STATUS_NO_CALL;
                
                //Enable and busy are reset with falling edge of enable input
                valid := FALSE;
                busy := FALSE;
                
            ELSE
                requestBufferHeader.numberOfRequests := tempNoOfRequests;
            END_IF;
        
        
            // Calculate runtime
            _instRuntime(signal := TRUE, duration := TIME_RUNTIME_TIMER);
            
            tempCurRuntime := TO_TIME(_instRuntime.elapsedTime);
            
            _instRuntime(signal := FALSE, duration := TIME_RUNTIME_TIMER);
            
            diagnostics.curRuntime := tempCurRuntime;
            
            IF (tempCurRuntime > diagnostics.maxRuntime) THEN
                diagnostics.maxRuntime := tempCurRuntime;
            END_IF;
            
            // Set maximum number of requests
            IF (TO_UINT(tempNoOfRequests) > diagnostics.maxNoOfRequests) THEN
                diagnostics.maxNoOfRequests := TO_UINT(tempNoOfRequests);
            END_IF;
        
        END_IF; // statFBBufferWatchdog.Q
        
        //----------------------------------------------------------------------------------------------
        //Error handling 
        //----------------------------------------------------------------------------------------------
        IF _errorUserCleared THEN
            busy := FALSE;
            valid := FALSE;
            error := TRUE;
            RETURN;
        
        ELSIF _errorAutoCleared THEN
            valid := FALSE;
            busy := TRUE;
            error := TRUE;
            RETURN;
        
        ELSE
            //Process normal output values
            valid := TRUE;
            error := FALSE;
            
            tempCountOfElements := TO_INT(GetCountOfElements(_requestBufferLowerBound, _requestBufferUpperBound));
        
            IF (tempNoOfRequests > tempCountOfElements - 1) THEN
                status := ResourcesStatus#STATUS_BUFFER_FULL; // Buffer is full at the moment
            ELSE
                status := ResourcesStatus#STATUS_SUBSEQUENT_CALL; //Set status for subsequent call  
            END_IF;
        END_IF;
    //----------------------------------------------------------------------------------------------
    END_FUNCTION_BLOCK
END_NAMESPACE
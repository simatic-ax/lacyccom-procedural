# HandleResource

## Principle of Operation

The HandleResource function block should be used for self-programmed function blocks that requests a resource from the central resource management implemented in the [ResourceManager](LAcycCom_ResourceManager.md) to get safely an acyclic resource.

> NOTE
>
> The input maxAssignedTime is optional and specifies for how long the resource should be assigned to the request. If the value at the input maxAssignedTime is less than the value in config.maxAssignedTime of [ResourceManager](LAcycCom_ResourceManager.md), the value of config.maxAssignedTime becomes effective instead.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestResource | BOOL | TRUE: A new resource is requested; FALSE: Resource is not needed any more |
| hardwareId | UINT | Hardware identifier of the hardware module |
| maxAssignedTime | TIME | Maximum time a resource is assigned to a request |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [ResourcesStatus](../enums/LAcycCom_ResourcesStatus.md) | Status identifier |
| waitingForResource | BOOL | TRUE: FB is waiting for a resource |
| resourceAssigned | BOOL | TRUE: Resource can be used |
| resourceReleased | BOOL | TRUE: Resource was released |
| usedHardwareId | UINT | Hardware identifier of the assigned buffer element |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [typeRequestBufferHeader](../types/LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [typeRequestBufferElement](../types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

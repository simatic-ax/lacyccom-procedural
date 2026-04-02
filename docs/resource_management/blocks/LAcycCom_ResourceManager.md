# ResourceManager

## Principle of Operation

The ResourceManager function block represents the central resource management for arbitration of DPV1 services. It assigns the acyclic data exchange resources to the requests stored in the request buffer. Other function blocks of this library get the permission to use an acyclic resource, e.g. used by calling `WriteRecord` or `ReadRecord` via the ResourceManager.

To obtain a resource from the ResourceManager two conditions must be fulfilled:

1. There must be at least one free resource for acyclic data exchange available.
2. Only one acyclic communication channel towards a device (e.g. ET200SP or SINAMICS S120) is allowed. Whenever a resource for the acyclic data exchange is reserved, all other function blocks (this could be function blocks from the [Drive Functions](../../drive_functions/index.md) or user programmed blocks embeding the [HandleResource](LAcycCom_HandleResource.md) function block) have to wait until the communication is finished.

The ResourceManager must be called in any `Main Task` every cycle.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| enable | BOOL | TRUE: Enable functionality of FB |
| config | [typeResourceManagerConfiguration](../types/LAcycCom_typeResourceManagerConfiguration.md#structure) | Configuration structure of ResourceManager FB |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| valid | BOOL | TRUE: Valid set of outputs available at the FB |
| busy | BOOL | TRUE: FB is working and new output values can be expected |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [ResourcesStatus](../enums/LAcycCom_ResourcesStatus.md) | Current status of FB |
| diagnostics | [typeResourceManagerDiagnostics](../types/LAcycCom_typeResourceManagerDiagnostics.md#structure) | Diagnostics information of FB |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [typeRequestBufferHeader](../types/LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [typeRequestBufferElement](../types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

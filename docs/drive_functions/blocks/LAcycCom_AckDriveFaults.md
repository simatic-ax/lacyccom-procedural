# LAcycCom_AckDriveFaults

## Principle of Operation

The AckDriveFaults function block can be used to acknowledge drive object faults by setting parameter p3981 to 1. This block internally uses the [LAcycCom_WriteDriveParams](LAcycCom_WriteDriveParams.md) function block.

> NOTE
>
> It is not possible to acknowledge drive object faults with this function block in the SINAMICS S210 drive system.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
| driveObjectId | INT | Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId) |
 | hardwareId | UINT | Hardware identifier of the hardware module |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| done | BOOL | TRUE: Commanded action has been completed successfully |
| busy | BOOL | TRUE: FB is not finished and new output values can be expected |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [LAcycCom_DriveFunctionStatus](../enums/LAcycCom_DriveFunctionStatus.md) | Status identifier |
| diagnostics | [LAcycCom_typeDriveDiagnostics](../types/LAcycCom_typeDriveDiagnostics.md#structure) | Diagnostics structure |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [LAcycCom_typeRequestBufferHeader](../../resource_management/types/LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [LAcycCom_typeRequestBufferElement](../../resource_management/types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

# LAcycCom_DriveComponentsActDeact

## Principle of Operation

The DriveComponentsActDeact function block is used to deactivate or activate drive object components like power unit and encoders in the SINAMICS control unit. This will be controlled by setting the parameters p0125 and p0145 in the drive object.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | Rising edge starts the functionality once |
| powerUnit | [LAcycCom_DriveComponentMode](../enums//LAcycCom_DriveComponentMode.md) | controls the state for the power unit |
| encoder1 | [LAcycCom_DriveComponentMode](../enums//LAcycCom_DriveComponentMode.md) | controls the state for encoder 1 |
| encoder2 | [LAcycCom_DriveComponentMode](../enums//LAcycCom_DriveComponentMode.md) | controls the state for encoder 2 |
| encoder3 | [LAcycCom_DriveComponentMode](../enums//LAcycCom_DriveComponentMode.md) | controls the state for encoder 3 |
| driveObjectId | INT := -1 | Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId) |
| hardwareId | UINT; | Hardware identifier of the hardware module |

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

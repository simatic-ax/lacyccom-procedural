# LAcycCom_DriveRamToRom

## Principle of Operation

The DriveRamToRom function block saves the volatile RAM data of a specific drive object to the retentive ROM. This will be controlled by setting the parameter p0071 in the drive object.

The drive object is specified via the drive object number or alternatively all drive objects of a multi drive system such as an S120 can be saved simultaneously (requires parameter p0977 to be present).

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
| driveObjectId | INT | Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId) |
| hardwareId | UINT | Hardware identifier of the hardware module |
| enableSavingOfWholeDriveSystem | BOOL | TRUE: Enable saving of all parameters of all drive objects of a multi drive system (e.g. S120). Note: parameter p977 must therefore be available at the addressed drive object. If p977 is not available p971 is written, i.e., the setting also works for single drive systems (e.g. G120) |

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

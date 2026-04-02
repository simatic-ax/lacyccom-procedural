# ReadDriveParams

## Principle of Operation

The ReadDriveParams function block allows to read multiple parameters via a dataset from a SINAMICS drive object or a PROFIdrive compliant drive.

> NOTE
>
> A maximum of 39 individual parameters can be read using one parameter dataset. In this case the maximum telegram length (240 bytes) is used.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
| parameterCount | INT | Count of parameters to read (-1: read all parameter in dataset) |
| driveObjectId | INT | Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId) |
| hardwareId | UINT | Hardware identifier of the hardware module |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| done | BOOL | TRUE: Commanded action has been completed successfully |
| busy | BOOL | TRUE: FB is not finished and new output values can be expected |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [DriveFunctionStatus](../enums/LAcycCom_DriveFunctionStatus.md) | Status identifier |
| diagnostics | [typeDriveDiagnostics](../types/LAcycCom_typeDriveDiagnostics.md#structure) | Diagnostics structure |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [typeRequestBufferHeader](../../resource_management/types/LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [typeRequestBufferElement](../../resource_management/types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |
| dataset | ARRAY[*] OF [typeDriveDatasetRead](../types/LAcycCom_typeDriveDatasetRead.md#structure) | Interface for dataset |

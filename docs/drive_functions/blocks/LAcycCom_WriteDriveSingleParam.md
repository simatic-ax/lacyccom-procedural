# LAcycCom_WriteDriveSingleParam

## Principle of Operation

The WriteDriveSingleParam function block allows to write a single parameter to a SINAMICS drive object or a PROFIdrive compliant drive.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
| driveObjectId | INT | Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId) |
| hardwareId | UINT | Hardware identifier of the hardware module |
| parameterNumber | UINT | Number of the parameter |
| index | UINT | Parameter index |
| writeSselector | LAcycCom_DatatypeSelector | type selector to specify the value that will be written to the parameter |
| realValue | REAL | Parameter value (real value) |
| dWordValue | DWORD | Parameter value (dword value) |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| done | BOOL | TRUE: Commanded action has been completed successfully |
| busy | BOOL | TRUE: FB is not finished and new output values can be expected |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [LAcycCom_DriveFunctionStatus](../enums/LAcycCom_DriveFunctionStatus.md) | Status identifier |
| errorValue | BYTE | Error number (16#FF: no error; else: see error list) |
| diagnostics | [LAcycCom_typeDriveDiagnostics](../types/LAcycCom_typeDriveDiagnostics.md#structure) | Diagnostics structure |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [LAcycCom_typeRequestBufferHeader](../../resource_management/types//LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [LAcycCom_typeRequestBufferElement](../../resource_management/types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

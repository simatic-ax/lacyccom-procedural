# ReadDriveMessagesDateTime

## Principle of Operation

The ReadDriveMessagesDateTime function block can be used to read active messages (alarms, faults and SI messages) from a drive object, sorted by time descending (latest first). The information provided are code, info and occurred date and time of message.

> NOTE
>
> To get the correct time, the clock of the SINAMICS drive unit must be synchronized with the clock of the SIMATIC controller, see [RTCSinamicsAcyclic](LAcycCom_RTCSinamicsAcyclic.md).
>
> This function block allows to read messages from S120, S210, G120 CU230P-2 and V90 PN. For other G120 CUs, use [ReadDriveMessagesOperatingHours](LAcycCom_ReadDriveMessagesOperatingHours.md).

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
| alarms | BOOL | TRUE: Enable reading of alarms |
| faults | BOOL | TRUE: Enable reading of faults |
| siMessages | BOOL | TRUE: Enable reading of SI messages |
| driveObjectId | INT := -1 | Optional: Identification number of the drive object (value <0: driveObjectId is not used, i.e. the corresponding drive object is only addressed via the hardwareId) |
| hardwareId | UINT | Hardware identifier of the hardware module |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| done | BOOL | TRUE: Commanded action has been completed successfully |
| busy | BOOL | TRUE: FB is not finished and new output values can be expected |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [DriveFunctionStatus](../enums/LAcycCom_DriveFunctionStatus.md) | Status identifier |
| diagnostics | [typeDriveDiagnostics](../types/LAcycCom_typeDriveDiagnostics.md#structure) | Diagnostics structure |
| messages | ARRAY[0..MESSAGES_COUNT_UPPER_LIM[^note]] OF [typeDriveMessage](../types/LAcycCom_typeDriveMessage.md#structure) | List of drive messages |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [typeRequestBufferHeader](../../resource_management/types/LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [typeRequestBufferElement](../../resource_management/types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

[^note]: This constant is defined within the ReadDriveMessagesDateTime function block and can not be changed.

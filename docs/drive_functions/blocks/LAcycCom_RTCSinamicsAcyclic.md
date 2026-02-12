# LAcycCom_RTCSinamicsAcyclic

## Principle of Operation

The RTCSinamicsAcyclic function block allows synchronizing the clock of the SIMATIC controller with the clock of the SINAMICS drive unit via acyclic data exchange (basic). The synchronization of the drive is made in UTC format (Universal Time Coordinated).

The following conditions have to be taken into account:

- A separate call must be programmed for each SINAMICS drive unit.
- The clocks must be synchronized each time that a SINAMICS drive unit powers up.
- It may be necessary to resynchronize the clock after a certain time.

> NOTE
>
> Further information about time synchronization is available in the SINAMICS S120 Functional Manual Communication, chapter [Time synchroinzation between the control and converter](https://support.industry.siemens.com/cs/de/en/view/109781721/114982142219).
>
> The accuracy of the synchronization is around 100ms or worse. It depends, amongst other things such as the OB1 cycle time and the CPU load in the drive control unit.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
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
| requestBufferHeader | [LAcycCom_typeRequestBufferHeader](../../resource_management/types//LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [LAcycCom_typeRequestBufferElement](../../resource_management/types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

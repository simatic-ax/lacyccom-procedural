# LAcycCom_RTCSinamics

## Principle of Operation

The RTCSinamics function block allows synchronizing the clock of the SIMATIC controller with the clock of the SINAMICS drive unit (with ping compensation). The synchronization of the drive is made in UTC format (Universal Time Coordinated).

The following conditions have to be taken into account:

- A separate call must be programmed for each SINAMICS drive unit.
- The clocks must be synchronized each time that a SINAMICS drive unit boots.
- It may be necessary to resynchronize the clock after a certain time.

When using the clock synchronization function between SIMATIC and SINAMICS, one of the standard telegrams 390, 391, 392, etc. must be selected for cyclic communication.

> NOTE
>
> Further information about time synchronization is available in the SINAMICS S120 Functional Manual Communication, chapter [Time synchroinzation between the control and converter](https://support.industry.siemens.com/cs/de/en/view/109781721/114982142219).
>
> This block writes bit 1 (rtcPing) of control word (CU_STW1). If user is overwriting this word afterwards (e.g. with instruction SETIO) in own application, he must connect the output rtcRealTimeSyncPING by using the slicing mechanism.

## Interface

### Input Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| execute | BOOL | TRUE: Rising edge starts the functionality once |
| hwIdTelegram39x | UINT | Hardware identifier of the telegram slot or subslot |

### Output Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| done | BOOL | TRUE: Commanded action has been completed successfully |
| busy | BOOL | TRUE: FB is not finished and new output values can be expected |
| error | BOOL | TRUE: Rising edge informs that an error occurred during the execution of the FB |
| status | [LAcycCom_DriveFunctionStatus](../enums/LAcycCom_DriveFunctionStatus.md) | Status identifier |
| rtcRealTimeSyncPING | BOOL | RTC real time synchronization PING // Optional. This bit has to be written in user program (slicing) if user writes complete control word (STW) in application |
| diagnostics | [LAcycCom_typeDriveDiagnostics](../types/LAcycCom_typeDriveDiagnostics.md#structure) | Diagnostics structure |

### In/Out Parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| requestBufferHeader | [LAcycCom_typeRequestBufferHeader](../../resource_management/types//LAcycCom_typeRequestBufferHeader.md#structure) | Interface for header of request buffer |
| requestBuffer | ARRAY[*] OF [LAcycCom_typeRequestBufferElement](../../resource_management/types/LAcycCom_typeRequestBufferElement.md#structure) | Interface for request buffer |

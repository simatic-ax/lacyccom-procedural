# Drive Functions

## Overview

The function blocks within the LAcycCom library facilitate communication with drive objects via DPV1 services. Specifically, they enable reading and writing of freely configurable parameter datasets using dataset 0xB02E and 0xB02F (asynchronous data exchange) from a drive object.

The process involves:

- Parameter Request: The user configures and sends a parameter request (read or write).
- Parameter Processing: The drive device processes the request.
- Parameter Response:
  - Success: A positive response is sent upon successful processing.
  - Error: If an error occurs, a specific error value indicating the cause is set in the response telegram.

Beyond basic parameter access, LAcycCom offers additional high-level functionalities for drive objects:

- Drive Object Control: Deactivation and activation of SINAMICS S120 drive objects and their components (e.g. power units, motor modules, encoders).
- Parameter Persistence: Saving drive object parameters to non-volatile memory (RAM2ROM).
- Simplified Integration: For these higher-level functionalities, the [HandleResource](../resource_management/blocks/LAcycCom_HandleResource.md) function block is often not directly required by the user, as correct handling of request buffers and resources is already integrated within them.

> Note
>
> More information about the structure of the dataset is available in the [SINAMICS S120 Function Manual Communication](https://support.industry.siemens.com/cs/ww/en/view/109781721).
</tr>

> Note
>
> As of LAcycom.Procedural V2.0 the base mode parameter acces global uses now dataset 0x0B02F instead of dataset 47, which is only supported by PROFINET capable devices. PROFIBUS capable devices are still being supported with V1.x.
</tr>

> Note
>
> It is recommended to use the base mode parameter access local (dataset 0xB02E), because it simplifies addressing as the drive object is identified solely via its hardware identifier. Using the base mode parameter access global (dataset 0xB02F), requires to specify a value at the driveObjectId input of the drive function blocks. The respective block internally switches between the two modes depending on the value of the input.

## Principle of Operation

The followig figure shows the principle of acyclic data exchange. The user sends the request for the specified parameters in the dataset to the device. This can be either a writing or reading request. When the parameter request was processed by the device, it sends an acknowledgement back. The requested parameters can be no either accessed to read or write their values. When this second request was processed by the device, it sends again an acknoledgement back to the controller. If an error occurs during the communication or processing of parameters, a specific error value will be set in the response telegram. All function blocks of the Drive Function are following this principle to exchange data via a drive system additionally utilizing the [Resourece Management](../resource_management/index.md).

![ReadingWritingData](../assets/DriveFunctions_ReadingWritingData.png)

## Content

### Function blocks

| Name                     | Description           |
| ------------------------ | --------------------- |
| [AckDriveFaults](blocks/LAcycCom_AckDriveFaults.md) | Function block to acknowledge faults at a drive object |
| [DriveActDeact](blocks/LAcycCom_DriveActDeact.md) | Function block to activate or deactivate drive objects in the SINAMICS control unit |
| [DriveComponentsActDeact](blocks/LAcycCom_DriveComponentsActDeact.md) | Function block to activate or deactivate drive object components (power unit and encoders) in the SINAMICS control unit |
| [DriveRamToRom](blocks/LAcycCom_DriveRamToRom.md) | Function block to save the volatile RAM data of specified drive object to the retentive ROM |
| [ReadDriveMessagesDateTime](blocks/LAcycCom_ReadDriveMessagesDateTime.md) | Function block to read active messages (alarms, fault and SI messages), sorted by time from a drive object |
| [ReadDriveMessagesOperatingHours](blocks/LAcycCom_ReadDriveMessagesOperatingHours.md) | Function block to read active messages (alarms and faults), sorted by time from a G120 control unit |
| [ReadDriveParams](blocks/LAcycCom_ReadDriveParams.md) | Function block to read multiple parameters via a dataset from a SINAMICS drive object |
| [ReadDriveSingleParam](blocks/LAcycCom_ReadDriveSingleParam.md) | Function block to read a single parameter from a SINAMICS drive object |
| [RTCSinamics](blocks/LAcycCom_RTCSinamics.md) | Function block to synchronize the clock of a SINAMICS control unit with the clock of the SIMATIC controller (with ping compensation)  |
| [RTCSinamicsAcyclic](blocks/LAcycCom_RTCSinamicsAcyclic.md) | Function block to synchronize the clock of a SINAMICS control unit with the clock of the SIMATIC controller (with acyclic data exchange) |
| [WriteDriveParams](blocks/LAcycCom_WriteDriveParams.md) | Function block to write multiple parameters via a dataset from a SINAMICS drive object |
| [WriteDriveSingleParam](blocks/LAcycCom_WriteDriveSingleParam.md) | Function block to write a single parameter from a SINAMICS drive object |

### Enums

| Name                     | Description           |
| ------------------------ | --------------------- |
| [DatatypeSelector](enums/LAcycCom_DatatypeSelector.md) | Contains possible data types used to specify the target value that is written to the drive object |
| [DriveComponentMode](enums/LAcycCom_DriveComponentMode.md) | Contains the different modes of a drive |
| [DriveFunctionStatus](enums/LAcycCom_DriveFunctionStatus.md) | Contains the status values for the drive functions |
| [DriveMessageType](enums/LAcycCom_DriveMessageType.md) | Contains the message types that are retrieved from the drive via LAcycCom_ReadDriveMessagesDateTime and LAcycCom_ReadDriveMessagesOperatingHours |
| [DriveValueFormats](enums/LAcycCom_DriveValueFormats.md) | Contains the format values of parameters from the drive object |
| [DriveValueErrors](enums/LAcycCom_DriveValueErrors.md) | Contains the error values of parameters from the drive object |

### Data Types

| Name                     | Description           |
| ------------------------ | --------------------- |
| [typeDriveDatasetWrite](types/LAcycCom_typeDriveDatasetWrite.md) | Defines a data structure that is used as a dataset to write parameters to a SINAMICS drive object |
| [typeDriveDatasetRead](types/LAcycCom_typeDriveDatasetRead.md) | Defines a data structure that is used as a dataset to read parameters from a SINAMICS drive object |
| [typeDriveDiagnostics](types/LAcycCom_typeDriveDiagnostics.md) | Defines a data structure that is used by drive functions to provide detailed diagnostics about the function block or internal states and error values of the drive state |
| [typeDriveMessage](types/LAcycCom_typeDriveMessage.md) | Defines a data structure that contains information about messages (alarms, faults SI messages) from a SINAMICS drive object |

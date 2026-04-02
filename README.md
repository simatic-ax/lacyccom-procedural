# @simatic-ax/lacyccom-procedural

## Description

The LAcycCom (Acyclic Communication) library for SIMATIC S7-1200/S7-1500 provides a collision-free coordination of communication resources in the CPU for acyclic data exchange via DPV1 services.

In case of user programmed blocks it is strongly recommend to use the provided resource management blocks when using any acyclic communications such as WriteRecord or ReadRecord, to avoid timing and priority issues with multiple requests for one device.

The following drive functions are available for drives compliant to PROFIdrive:

- Read/Write parameters in the drive system
- Activate/Deactivate complete drive objects
- Activate/Deactivate components of drive objects
- Acknowledge errors of drive objects
- Saving of volatile RAM data into the retentive ROM memory (RAM2ROM)
- Time synchronization of CPU and drive system to achieve a chronological order of alarms and messages

## Getting started

Install with Apax:

> If not yet done login to the GitHub registry first.
> More information you'll find [here](https://github.com/simatic-ax/.github/blob/main/docs/personalaccesstoken.md)

```cli
apax add @simatic-ax/lacyccom-procedural
```

Add the namespace in your ST code:

```iec-st
USING Simatic.Ax.LAcycCom.Procedural
```

## Library functionality

The library is divided into the sections [Resource Management](docs/resource_management/index.md) where the allocation and handling of resources are centrally managed and [Drive Functions](docs/drive_functions/index.md) which represents various functions to interact via acyclic communication with a SINAMICS drive system.

### Resource Management

| Function Blocks          | Description           |
| ------------------------ | --------------------- |
| [ResourceManager](docs/resource_management/blocks/LAcycCom_ResourceManager.md) | Function block to manage state of multiple arbitrary resources |
| [HandleResource](docs/resource_management/blocks/LAcycCom_HandleResource.md) | Function block for user programmed blocks to request the state of a resource centrally managed in the resource manager |

### Drive Functions

| Function Blocks          | Description           |
| ------------------------ | --------------------- |
| [AckDriveFaults](docs/drive_functions/blocks/LAcycCom_AckDriveFaults.md) | Function block to acknowledge faults at a drive object |
| [DriveActDeact](docs/drive_functions/blocks/LAcycCom_DriveActDeact.md) | Function block to activate or deactivate drive objects in the SINAMICS control unit |
| [DriveComponentsActDeact](docs/drive_functions/blocks/LAcycCom_DriveComponentsActDeact.md) | Function block to activate or deactivate drive object components (power unit and encoders) in the SINAMICS control unit |
| [DriveRamToRom](docs/drive_functions/blocks/LAcycCom_DriveRamToRom.md) | Function block to save the volatile RAM data of specified drive object to the retentive ROM |
| [ReadDriveMessagesDateTime](docs/drive_functions/blocks/LAcycCom_ReadDriveMessagesDateTime.md) | Function block to read active messages (alarms, fault and SI messages), sorted by time from a drive object |
| [ReadDriveMessagesOperatingHours](docs/drive_functions/blocks/LAcycCom_ReadDriveMessagesOperatingHours.md) | Function block to read active messages (alarms and faults), sorted by time from a G120 control unit |
| [ReadDriveParams](docs/drive_functions/blocks/LAcycCom_ReadDriveParams.md) | Function block to read multiple parameters via a dataset from a SINAMICS drive object |
| [ReadDriveSingleParam](docs/drive_functions/blocks/LAcycCom_ReadDriveSingleParam.md) | Function block to read a single parameter from a SINAMICS drive object |
| [RTCSinamics](docs/drive_functions/blocks/LAcycCom_RTCSinamics.md) | Function block to synchronize the clock of a SINAMICS control unit with the clock of the SIMATIC controller (with ping compensation)  |
| [RTCSinamicsAcyclic](docs/drive_functions/blocks/LAcycCom_RTCSinamicsAcyclic.md) | Function block to synchronize the clock of a SINAMICS control unit with the clock of the SIMATIC controller (with acyclic data exchange) |
| [WriteDriveParams](docs/drive_functions/blocks/LAcycCom_WriteDriveParams.md) | Function block to write multiple parameters via a dataset from a SINAMICS drive object |
| [WriteDriveSingleParam](docs/drive_functions/blocks/LAcycCom_WriteDriveSingleParam.md) | Function block to write a single parameter from a SINAMICS drive object |

## Examples

### Reading a single parameter from a S120 drive

```iec-st
USING Simatic.Ax.LAcycCom.Procedural;

PROGRAM SampleProgramS120
    VAR_INPUT
        readParam : BOOL;
    END_VAR

    VAR_OUTPUT
        value : REAL;
    END_VAR

    VAR_EXTERNAL
        DRIVE_BLUE_TEL105 : UINT;
    END_VAR
    
    VAR
        _resourceManagerConfig : typeResourceManagerConfiguration;
        _requestBufferHeader : typeRequestBufferHeader;
        _requestBuffer : ARRAY[1..10] OF typeRequestBufferElement;
        _instResourceManager : ResourceManager;
        _instReadDriveSingleParam : ReadDriveSingleParam;
    END_VAR

    // call resource manager
    _instResourceManager(enable := TRUE, 
                         config := _resourceManagerConfig, 
                         requestBufferHeader := _requestBufferHeader, 
                         requestBuffer := _requestBuffer);

    // call read drive single param
    _instReadDriveSingleParam(hardwareId := DRIVE_BLUE_TEL105, 
                              parameterNumber := UINT#1082, // maximum speed 
                              requestBufferHeader := _requestBufferHeader, 
                              requestBuffer := _requestBuffer);
                              
    // resource manager needs to be valid, before executing function blocks from Drive Functions
    IF _instResourceManager.valid THEN
        // execute read single parameter
        _instReadDriveSingleParam.execute := readParam;

        // reflect value to output
        value := _instReadDriveSingleParam.realValue;
    ELSE
        _instReadDriveSingleParam.execute := FALSE;
    END_IF;
END_PROGRAM
```

### Writing multiple parameters to a S210 drive

```iec-st
USING Simatic.Ax.LAcycCom.Procedural;

PROGRAM SampleProgramS210
    VAR_INPUT
        writeParams : BOOL;
    END_VAR

    VAR_OUTPUT
        done: BOOL;
        error: BOOL;
    END_VAR

    VAR_EXTERNAL
        DRIVE_1_MAP : UINT;
    END_VAR
        
    VAR
        _resourceManagerConfig : typeResourceManagerConfiguration;
        _requestBufferHeader : typeRequestBufferHeader;
        _requestBuffer : ARRAY[1..10] OF typeRequestBufferElement;
        _instResourceManager : ResourceManager;
        _instWriteDriveParams : WriteDriveParams;
        _dataset : ARRAY[1..3] OF typeDriveDatasetWrite;
    END_VAR
        
    // call resource manager
    _instResourceManager(enable := TRUE, 
                         config := _resourceManagerConfig, 
                         requestBufferHeader := _requestBufferHeader, 
                         requestBuffer := _requestBuffer);

    // call write drive params
    _instWriteDriveParams(hardwareId := DRIVE_1_MAP,
                          parameterCount := -1,
                          dataset := _dataset,
                          requestBufferHeader := _requestBufferHeader,
                          requestBuffer := _requestBuffer);

    // resource manager needs to be valid, before executing function blocks from Drive Functions
    IF _instResourceManager.valid THEN

        // define parameters and their values
        _dataset[1].parameterNumber := UINT#1083; // positive speed limit
        _dataset[1].valueSelector := DatatypeSelector#TYPE_REAL;
        _dataset[1].realValue := 6000;
        _dataset[2].parameterNumber := UINT#1086; // negative speed limit
        _dataset[2].valueSelector := DatatypeSelector#TYPE_REAL;
        _dataset[2].realValue := -6000;
        _dataset[3].parameterNumber := UINT#1121; // ramp down time
        _dataset[3].valueSelector := DatatypeSelector#TYPE_REAL;
        _dataset[3].realValue := REAL#1.5;

        // execute write drive parameters
        _instWriteDriveParams.execute := writeParams;

        // reflect state to outputs
        done := _instWriteDriveParams.done;
        error := _instWriteDriveParams.error;
    ELSE
        _instWriteDriveParams.execute := FALSE;

        done := FALSE;
        error := FALSE;
    END_IF;
END_PROGRAM
```

## Contribution

Thanks for your interest in contributing. Anybody is free to report bugs, unclear documentation, and other problems regarding this repository in the Issues section or, even better, is free to propose any changes to this repository using a pull request.

## License and Legal information

Please read the [Legal information](LICENSE)

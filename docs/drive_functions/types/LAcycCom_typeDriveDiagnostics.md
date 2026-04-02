# typeDriveDiagnostics

## Description

Defines a data structure that is used by drive functions to provide detailed diagnostics about the function block or internal states and error values of the drive state.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| status | WORD | Status identifier when error occurred |
| subfunctionStatus | WORD | Block status or error information |
| stateNumber | SINT | State of the FB when error occurred |
| driveObjectId | SINT | Identification number of the drive object |
| hardwareId | UINT | Hardware identifier of the hardware module |
| parameterCount | INT | Total amount of parameters |
| firstParameterError | INT | Number of parameter at which the error occurred (-1: no parameter with error) |
| errorValue | [DriveValueErrors](../enums/LAcycCom_DriveValueErrors.md) | Specific PROFIdrive error value (16#FF: no error) |

## Usage

This type is used by every function block of the drive function to provide diagnostics (output parameter of function block).

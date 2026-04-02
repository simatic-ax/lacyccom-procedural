# typeDriveDatasetRead

## Description

Defines a data structure that is used as a dataset to read parameters from a SINAMICS drive object.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| parameterNumber | UINT|  Number of the parameter |
| index | UINT |  Parameter index |
| realValue | REAL |  Parameter value as real |
| dwordValue | DWORD|  Parameter value as dword |
| lrealValue | LREAL | Parameter value as real |
| errorValue | [DriveValueErrors](../enums/LAcycCom_DriveValueErrors.md) |  Error value (16#FF: no error) |
| format | [DriveValueFormats](../enums/LAcycCom_DriveValueFormats.md) | Format of the value |

## Usage

This type is used in arrays that describes a dataset (parameter, index value and and error value) in the function block [LAcycCom_ReadDriveParams](../blocks/LAcycCom_ReadDriveParams.md#inout-parameters).

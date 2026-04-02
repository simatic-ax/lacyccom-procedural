# typeDriveDatasetWrite

## Description

Defines a data structure that is used as a dataset to write parameters to a SINAMICS drive object.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| parameterNumber | UINT|  Number of the parameter |
| index | UINT |  Parameter index |
| valueSelector | [DatatypeSelector](../enums/LAcycCom_DatatypeSelector.md) | Type selector to specify the value of this dataset that will be written to the parameter |
| realValue | REAL |  Parameter value as real |
| dwordValue | DWORD|  Parameter value as dword |
| lrealValue | LREAL | Parameter value as real |
| errorValue | [DriveValueErrors](../enums/LAcycCom_DriveValueErrors.md) |  Error value (16#FF: no error) |

## Usage

This type is used in arrays that describes a dataset (parameter, index value and and error value) in the function block [LAcycCom_WriteDriveParams](../blocks/LAcycCom_WriteDriveParams.md#inout-parameters).

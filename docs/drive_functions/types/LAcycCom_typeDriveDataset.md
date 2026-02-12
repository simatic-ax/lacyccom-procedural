# LAcycCom_typeDriveDataset

## Description

Defines a data structure that is used as a dataset to read/write parameters to a SINAMICS drive object.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| parameterNumber | UINT|  Number of the parameter |
| index | UINT |  Parameter index |
| writeSelector | [LAcycCom_DatatypeSelector](../enums/LAcycCom_DatatypeSelector.md) |LAcycCom_ReadDriveParams: no function; LAcycCom_WriteDriveParams: type selector to specify the value of this dataset that will be written to the parameter |
| realValue | REAL |  Parameter value as real |
| dwordValue | DWORD|  Parameter value as dword |
| errorValue | BYTE |  Error number (16#FF: no error; else: see error list) |

## Usage

This type is used in arrays that describes a dataset (parameter, index value and and error value) in the function blocks [LAcycCom_WriteDriveParams](../blocks/LAcycCom_WriteDriveParams.md#inout-parameters) and [LAcycCom_ReadDriveParams](../blocks/LAcycCom_ReadDriveParams.md#inout-parameters).

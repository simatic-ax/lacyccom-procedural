# typeActiveRequest

## Description

Defines a data structure to describe an element from the active requests stored in the header of the buffer.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| bufferIndex | INT | Index of buffer element |
| maxAssignedTime | TIME | Maximum time a resource is assigned to a request |

## Usage

This type is used in arrays to exchange data about an active request stored in [typeRequestBufferHeader](LAcycCom_typeRequestBufferHeader.md#structure).

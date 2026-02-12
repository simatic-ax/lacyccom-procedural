# LAcycCom_typeRequestBufferHeader

## Description

Defines a data structure to control and provide information of the buffer used by this appliaction to share and manage state of resources.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| lockBuffer | BOOL | TRUE: Request buffer DB is locked by application |
| nextFreeElement | INT | Next free request element in request buffer |
| firstQueueElement | INT | Index of oldest element existing in request buffer |
| numberOfRequests | INT | Number of existing requests in request buffer not released yet |
| bufferLowerBound | DINT | Start index of buffer |
| bufferUpperBound | DINT | End index of buffer |
| activeRequests | ARRAY[0..[LAcycCom_ResourcesConstants#ACTIVE_REQUESTS](../enums/LAcycCom_ResourcesConstants.md)] OF [LAcycCom_typeActiveRequest](LAcycCom_typeActiveRequest.md) | Currently enabled request elements |

## Usage

This type is used by every function block of this appliaction to exchange data via the buffer (in/out parameter of function block).

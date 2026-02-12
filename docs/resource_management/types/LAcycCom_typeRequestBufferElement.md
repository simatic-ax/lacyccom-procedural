# LAcycCom_typeRequestBufferElement

## Description

Defines a data structure to describe an element from the buffer used by this appliaction to share and manage state of resources.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| state | BYTE | State of the request. Bit 0: allocate new buffer element; Bit 1: buffer element is assigned; Bit 2: release buffer element; Bit 3: request rejected |
| hardwareId | UINT | Hardware identifier of the hardware module |
| queueElementPrevious | INT | Element in queue before this element |
| queueElementNext | INT | Element in queue after this element |
| queueTime | TIME | Time duration element is in queue |

## Usage

This type is used in every function block of this appliaction to exchange data via the buffer (in/out parameter of function block).

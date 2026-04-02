# typeDriveMessage

## Description

Defines a data structure that contains information about messages (alarms, faults SI messages) from a SINAMICS drive object.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| messageType | DriveMessageType | type of drive message |
| code | UINT | code of the drive message (see respective drive function manual for further details) |
| info | UDINT | info of the drive message (see respective drive function manual for further details) |
| comeDateAndTime | LDATE_AND_TIME | timestamp of incoming message |

## Usage

This type is used in arrays that describes a message (alarms, faults SI messages) in the function blocks [ReadDriveMessagesDateTime](../blocks/LAcycCom_ReadDriveMessagesDateTime.md#output-parameters) and [ReadDriveMessagesOperatingHours](../blocks/LAcycCom_ReadDriveMessagesOperatingHours.md#output-parameters).

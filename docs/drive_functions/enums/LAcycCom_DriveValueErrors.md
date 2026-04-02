# DriveValueErrors

| Symbol | Value | Description |
| ------ | ----- | ----------- |
| ILLEGAL_PARAMETER | USINT#16#0 | Access to a parameter that does not exist |
| PARAMETER_CANNOT_BE_CHANGED | USINT#16#01 | Modification access to a parameter value that cannot be changed |
| LIMIT_EXCEEDED | USINT#16#02 | Modification access with value outside value limits |
| INVALID_SUBINDEX | USINT#16#03 | Access to a subindex that does not exist |
| NO_ARRAY | USINT#16#04 | Access with subindex to an unindexed parameter |
| WRONG_DATATYPE | USINT#16#05 | Modification access with a value that does not match the data type of the parameter |
| ILLEGEL_SET_OPERATION | USINT#16#06 | Modification access with a value not equal to 0 in a case where this is not allowed |
| DESCRIPTION_CANNOT_BE_CHANGED | USINT#16#07 | Modification access to a description element that cannot be changed |
| NO_DESCRIPTION_AVAILABLE | USINT#16#09 | Access to a description that does not exist |
| READ_JOB_REFUSED | USINT#16#10 | The read request is refused because know-how protection is active |
| NO_OPERATING_PRIORITY | USINT#16#0B | Modification access with no operating priority |
| NO_TEXT_ARRAY_EXISTS | USINT#16#0F | Access to a text array that does not exist |
| REQUEST_NOT_POSSIBLE | USINT#16#11 | Access is temporarily not possible for unspecified reasons |
| ILLEGAL_VALUE | USINT#16#14 | Modification access with a value that is within the limits but is illegal for other permanent reasons |
| RESPONSE_PAYLOAD_TOO_LONG | USINT#16#15 | The length of the present response exceeds the maximum transfer length |
| ILLEGAL_PARAMETER_ADDRESS | USINT#16#16 | Illegal or unsupported value for attribute, number of elements, parameter number, subindex or a combination of these |
| ILLEGAL_FORMAT | USINT#16#17 | Write request: Illegal or unsupported parameter data format |
| PAYLOAD_QUANTITIES_INCONSISTENT | USINT#16#18 | Write request: A mismatch exists between the number of values in the parameter data and the number of elements in the parameter address |
| DRIVE_OBJECT_DOES_NOT_EXIST | USINT#16#19 | You have attempted to access a drive object that does not exist |
| PARAMETER_TEXT_CANNOT_BE_CHANGED | USINT#16#20 | Parameter text can not be changed |
| SERVICE_NOT_SUPPORTED | USINT#16#21 | Illegal or unknown request ID |
| PARAMETER_DEACTIVATED | USINT#16#65 | You have tried to access a parameter that does perform a function in its current state |
| WRITE_ACCESS_FOR_ENABLED_CONTROLLER | USINT#16#6B | Write access is possible while the device is in the "Controller enable" state |
| PARAMETER_UNKNOWN_UNIT | USINT#16#6C | Affects respective parameter |
| PARAMETER_STATE_ENCODER_REQUIRED | USINT#16#6D | Write access only in the commissioning state encoder (p0010 = 4) |
| PARAMETER_STATE_MOTOR_REQUIRED | USINT#16#6E | Write access only in the commissioning state motor (p0010 = 3) |
| PARAMETER_STATE_POWER_UNIT_REQUIRED | USINT#16#6F | Write access only in the commissioning state power unit (p0010 = 2) |
| PARAMETER_MODE_QUICK_COMMISSIONING_REQUIRED | USINT#16#70 | Write access only in the commissioning mode quick commissioning (p0010 = 1) |
| PARAMETER_MODE_READY_REQUIRED | USINT#16#71 | Write access only in the commissioning mode ready (p0010 = 0) |
| PARAMETER_STATE_RESET | USINT#16#72 | Write access only in the commissioning state ready (p0010 = 30) |
| PARAMETER_STATE_SAFETY | USINT#16#73 | Write access only in the commissioning state safety (p0010 = 95) |
| PARAMETER_STATE_TECH_APP | USINT#16#74 | Write access only in the commissioning state technology application (p0010 = 5) |
| PARAMETER_STATE_COMMISSIONING | USINT#16#75 | Write access only in the commissioning state (p0010 <> 0) |
| PARAMETER_STATE_DOWNLOAD | USINT#16#76 | Write access only in the commissioning state download (p0010 = 29) |
| PARAMETER_STATE_DRIVE_CONFIGURATION | USINT#16#78 | Write access only in the commissioning state drive configuration (p0009 = 3) |
| PARAMETER_STATE_DEFINE_DRIVE | USINT#16#79 | Write access only in the commissioning state define drive type (p0009 = 2) |
| PARAMETER_STATE_DATA_RECORD_BASE | USINT#16#7A | Write access only in the commissioning state data record base configuration (p0009 = 4) |
| PARAMETER_STATE_DEVICE_CONFIGURATION | USINT#16#7B | Write access only in the commissioning state device configuration (p0009 = 1) |
| PARAMETER_STATE_DEVICE_DOWNLOAD | USINT#16#7C | Write access only in the commissioning state device download (p0009 = 29) |
| PARAMETER_STATE_DEVICE_PARAMETER_RESET | USINT#16#7D | Write access only in the commissioning state device parameter reset (p0009 = 30) |
| PARAMETER_STATE_DEVICE_READY | USINT#16#7E | Write access only in the commissioning state device ready (p0009 = 0) |
| PARAMETER_STATE_DEVICE | USINT#16#7F | Write access only in the commissioning state device (p0009 <> 0) |
| TRANSFER_IS_BLOCKED | USINT#16#82 | Transfer of master control is blocked by BI: p0806 |
| REQUESTED_BICO_INTERCONNECTION_NOT_POSSIBLE | USINT#16#83 | Requested BICO interconnection is not possible |
| PARAMETER_CHANGE_INHIBITED | USINT#16#84 | Parameter change inhibited (refer to p0300, p0400, p0922) |
| PARAMETER_ACCESS_METHOD_NOT_DEFINED | USINT#16#85 | Parameter access method not defined |
| PARAMETER_WRITE_JOB_DENIED | USINT#16#87 | Write job will not be executed |
| BELOW_CURRENT_VALID_LIMIT | USINT#16#C8 | Below current valid limit |
| ABOVE_CURRENT_VALID_LIMIT | USINT#16#C9 | Above current valid limit |
| WRITE_ACCESS_NOT_PERMITTED | USINT#16#CC | Write access not permitted |

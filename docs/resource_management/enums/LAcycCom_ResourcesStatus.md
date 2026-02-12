# LAcycCom_ResourcesStatus

| Symbol | Value | Description |
| ------ | ----- | ----------- |
| STATUS_RESOURCE_RELEASED | WORD#16#0000 | Resource was successfully released |
| STATUS_NO_CALL | WORD#16#7000 | Execution finished without errors |
| STATUS_FIRST_CALL | WORD#16#7001 | First call of FB after enabling |
| STATUS_SUBSEQUENT_CALL | WORD#16#7002 | Waiting for a resource |
| STATUS_BUFFER_FULL | WORD#16#7003 | Buffer is full; no more elements can be added |
| STATUS_RESOURCE_ASSIGNED | WORD#16#7004 | Everything is okay and resource is assigned |
| WARN_BUFFER_LOCKED | WORD#16#7100 | Buffer lock time expired; lock is reset by FB |
| WARN_WRONG_HARDWARE_ID | WORD#16#7101 | Internal called system instruction ReadSlotFromHardwareID returned an error (The address specified at the hardwareID parameter is invalid) |
| ERR_RESOURCE_REJECTED_WHILE_WAITING | WORD#16#8400 | Request was rejected by FB |
| ERR_RESOURCE_RELEASED_WHILE_WAITING | WORD#16#8401 | Request was already released |
| ERR_ALLOCATION | WORD#16#8600 | Buffer is full or buffer is locked or resource manager is inactive |
| ERR_INVALID_BUF_IDX | WORD#16#8601 | Buffer index is invalid |
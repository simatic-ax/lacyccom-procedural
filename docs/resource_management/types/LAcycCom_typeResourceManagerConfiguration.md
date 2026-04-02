# typeResourceManagerConfiguration

## Description

Defines a data structure to describe configuration parameter for the resource management.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| timeoutBufferLock | TIME | Timeout for locking of complete request buffer, that means resource manager has no access |
| maxQueueTime | TIME | Maximum waiting time of a request waiting in queue before releasing the element is enforced by resource manager |
| maxAssignedTime | TIME | Maximum time a resource is assigned to a request |
| delayReleaseAfterReject | TIME | Delay for releasing resource after it was rejected by resource manager |

## Usage

This type is used as a configuration structure for the function block [ResourceManager](../blocks/LAcycCom_ResourceManager.md#input-parameters).

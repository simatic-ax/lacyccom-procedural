# LAcycCom_typeResourceManagerDiagnostics

## Description

Defines a data structure to provide diagnostics about the resource manager.

## Structure

| Field | Type | Description |
| ----- | ---- | ----------- |
| maxNoOfRequests | UINT | Maximum number of requests in use in request buffer |
| curRuntime | TIME | Runtime of last call |
| maxRuntime | TIME | Maximum runtime of FB |

## Usage

This type is used as a diagnostics structure for the function block [LAcycCom_ResourceManager](../blocks/LAcycCom_ResourceManager.md#output-parameters).

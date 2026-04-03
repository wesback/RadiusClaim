# Radius Entra Statestore Backfill

Use this pattern when a Radius Azure Blob Dapr state store fails after shared-key auth is removed or disabled.

## Signal

- `rad env show` shows the state-store recipe rendered with Entra inputs
- `rad resource show Applications.Dapr/stateStores statestore -a <app>` reports `Failed`
- `az storage account show` shows `allowSharedKeyAccess: false`
- `az role assignment list --scope <storage-account-id>` has no `Storage Blob Data Contributor`
- `dapr components -k -A` or `kubectl get components.dapr.io -A` shows no projected components

## Fix

1. Grant `Storage Blob Data Contributor` to the Dapr principal on the Blob account.
2. Rerun `./scripts/deploy-dapr-components.sh --resource-group <rg> --namespace <workload-namespace>`.
3. Verify `statestore`, `pubsub`, and `platform-secrets` are present in the workload namespace.

## Why it matters

This repo uses Radius as the wiring control plane and Dapr components as the runtime contract. If the statestore recipe cannot complete authorization, the Dapr components never get projected and the app looks broken even though the Azure backing resources partly exist.

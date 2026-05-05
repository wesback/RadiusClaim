# Radius Recipes

This directory contains the Azure-backed Radius recipes used by the repo's Kubernetes-first deployment path.

## What these recipes do

Each recipe:

- accepts the Radius-provided `context` object
- provisions one Azure backing service
- emits `values` plus structured `resourceMetadata.dapr` for downstream automation
- relies on Microsoft Entra / workload identity metadata instead of shared secrets

## Current backing services

- **state-store.bicep** — Azure Database for PostgreSQL Flexible Server for Dapr state and actor storage
- **pubsub.bicep** — Azure Service Bus for Dapr pub/sub messaging
- **secrets.bicep** — Azure Key Vault for Dapr secret management

## Projection model

These recipes provision Azure resources only. They do **not** directly create Kubernetes `components.dapr.io` CRDs in the current repo flow.

Instead:

1. Radius deploys the recipe and tracks the Azure resources.
2. The recipe publishes Dapr-facing metadata in `resourceMetadata.dapr` and `values`.
3. `scripts/bootstrap.sh` and CI run `scripts/apply-dapr-components-from-recipes.sh`.
4. That script projects `statestore`, `pubsub`, and `platform-secrets` into the workload namespace.

This keeps the recipe contract declarative while acknowledging the current Radius component-projection gap honestly.

## Resource naming

The current Azure recipes use these prefixes:

- **State store:** `pgstate{suffix}`
- **Pub/Sub:** `pubsubrc{suffix}`
- **Secret store:** `kvrc{suffix}`

Deployments can use deterministic naming (`uniqueString`) or pass demo-friendly suffix overrides where supported by the environment/bootstrap flow.

## Implementation notes

- RBAC-only authorization is used where supported; no legacy Key Vault access policies
- Recipe metadata is the source of truth for Dapr component projection
- Post-deploy CLI steps still exist where Radius v0.56 requires workarounds for child resources or cross-scope RBAC

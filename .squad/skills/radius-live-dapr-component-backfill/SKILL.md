---
name: "radius-live-dapr-component-backfill"
description: "Recover a live Radius deployment when Applications.Dapr resources succeeded but no Kubernetes Dapr Component objects were projected"
domain: "platform"
confidence: "high"
source: "graham-earned"
tools:
  - name: "kubectl"
    description: "Verify whether Dapr Component CRs exist in the workload namespace and inspect sidecar logs"
    when: "Radius resources look healthy but daprd says a component is not configured"
  - name: "rad"
    description: "Confirm the Radius environment, app, and Applications.Dapr resources all report Succeeded"
    when: "You need to distinguish control-plane success from missing Kubernetes projection"
  - name: "az"
    description: "Fetch Azure backing-resource IDs/credentials and grant data-plane RBAC when emergency backfill is required"
    when: "The missing Dapr component needs Azure auth that the runtime can actually use"
---

## Context

Use this when a live Kubernetes deployment created by Radius shows app pods and sidecars, but runtime calls fail with messages like `state store statestore is not configured` or pub/sub never initializes. The critical pattern is that Radius claims the Dapr resources succeeded, yet Kubernetes has no corresponding `components.dapr.io` objects.

## Patterns

### Prove the issue is missing component projection

- Check Radius first:
  - `rad env list`
  - `rad app list`
  - `rad resource list -g <group>`
- Then check Kubernetes directly:
  - `kubectl get components.dapr.io -A`
- If Radius says `Applications.Dapr/*` resources succeeded **and** Kubernetes still has zero components, do not spend time on component scopes first. The higher-signal problem is that no Dapr `Component` CRs were projected at all.

### Use sidecar startup logs as the truth source

- Healthy sidecars should log `Component loaded: <name> (...)`.
- If the sidecar only loads `kubernetes (secretstores.kubernetes/v1)` and never loads `statestore`/`pubsub`, the runtime symptom is explained immediately.
- If the sidecar crashloops during component init, inspect the live `Component` CRs before blaming app annotations:
  - `KeyBasedAuthenticationNotPermitted` points at a Blob statestore auth mismatch (`accountKey` against a storage account that disallows shared-key auth).
  - `pubsub.azure.servicebus.topics` must not carry both `namespaceName` and `connectionString`.

### Re-run `rad deploy` once to rule out staleness

- A single idempotent `rad deploy infra/radius/app.bicep ...` is worth doing to separate “stale deployment” from “projection gap”.
- If the redeploy refreshes workloads/resources but `kubectl get components.dapr.io -A` is still empty, the deployment is not merely stale.

### Backfill in the workload namespace, not the environment namespace

- For this repo, the workload namespace is `radiusclaim-azure-radiusclaim`.
- Emergency Dapr components must land where the app sidecars can see them.
- Do not assume the environment namespace (`radiusclaim-azure`) will help if it is empty or if sidecars run elsewhere.

### Match Azure auth to the backing service's actual policy

- Azure Blob state:
  - If the storage account rejects shared-key auth (`KeyBasedAuthenticationNotPermitted`), use the same Microsoft Entra principal Radius already uses for recipe provisioning. Carry `azureTenantId` + `azureClientId` into the component, add `azureClientSecret` only when running in service-principal mode, and grant `Storage Blob Data Contributor`.
  - Prefer repairing RBAC and regenerating the component over trying to re-enable shared keys. In this repo's tenant, shared-key re-enable is no longer the valid operator path.
- Azure Service Bus topics:
  - Use **either** `connectionString`
  - **or** `namespaceName` + Azure auth
  - Never both; daprd rejects that configuration.

### Validate with an application action, not only with object existence

- After backfill, confirm:
  - `kubectl get components.dapr.io -n <workload-namespace>`
  - sidecar logs show `Component loaded: ...`
  - one real request (for this repo: `POST /expenses` then `GET /expenses/{id}`) succeeds

## Examples

- Radius app model: `infra/radius/app.bicep`
- Radius environment: `infra/radius/environments/azure-radius.bicep`
- Azure recipes:
  - `infra/radius/recipes/azure/state-store.bicep`
  - `infra/radius/recipes/azure/pubsub.bicep`
- Incident namespace pair:
  - environment: `radiusclaim-azure`
  - workload: `radiusclaim-azure-radiusclaim`

## Anti-Patterns

- Assuming the problem is a missing app scope before checking whether the component exists at all.
- Treating a `Succeeded` Radius Dapr resource as proof that Kubernetes received the component.
- Reusing Blob `accountKey` auth after the storage account or policy disables shared-key access.
- Treating the Radius Azure credential and the Dapr runtime credential as separate stories when a single Entra principal keeps the model smaller and more teachable.
- Supplying both `namespaceName` and `connectionString` to `pubsub.azure.servicebus.topics`.
- Backfilling components into the environment namespace when workloads and sidecars live in a separate workload namespace.

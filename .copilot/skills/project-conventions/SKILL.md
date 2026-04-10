---
name: "project-conventions"
description: "Core conventions and patterns for this codebase"
domain: "project-conventions"
confidence: "high"
source: "graham-phase1"
---

## Context

RadiusClaim is a small reference sample that demonstrates Dapr portability and Radius platform wiring with Kubernetes-first deployment, using AKS as the managed Azure example.

## Patterns

### Platform Modeling

- Keep service topology and dependency wiring in Radius under `infra/radius/`.
- Model app-to-app calls with Radius `connections` and model Dapr dependencies as `Applications.Dapr/*` resources.
- Add the Dapr sidecar through the Radius container extension instead of hand-authoring sidecar manifests.

### File Structure

- `infra/radius/app.bicep` is the authoritative application model for services and shared Dapr components.
- `infra/radius/modules/` holds reusable Radius modules, such as the shared container-service module.
- `infra/radius/environments/` stores environment-specific parameter files.
- `infra/radius/recipes/azure/` holds Azure recipe stubs or implementations when platform backing resources are needed.
- `infra/dapr/local/` is reserved for local-only Dapr component overlays and the minimal emulator support files they need; it complements Radius rather than replacing it.

### Azure Targeting

- Treat Radius-managed Kubernetes as the intended runtime target in parameters and deployment conventions.
- Use AKS as the managed Azure example, while keeping Arc-enabled Kubernetes / Azure Local and self-managed clusters in frame when Radius prerequisites are met.
- Keep application code cloud-agnostic by wiring state, pub/sub, and secrets through Dapr component connections instead of direct Azure SDK dependencies.
- Defer Azure-specific backing resource implementation into recipes rather than embedding it in the app model, and say so plainly instead of implying full cloud agnosticism.
- Keep Dapr component names consistent between `RadiusClaimDapr` constants, Radius resources, and local overlays (`statestore`, `pubsub`) so environment changes do not leak into app code.

### Validation

- Validate Radius Bicep with `az bicep build --file infra/radius/app.bicep`.
- Validate placeholder recipe files with `az bicep build` before moving on to environment work.

## Examples

```bicep
resource expenseStateStore 'Applications.Dapr/stateStores@2023-10-01-preview' = {
  name: 'expense-state'
  location: 'global'
  properties: {
    environment: environment
    application: application
  }
}
```

## Anti-Patterns

- **Raw Kubernetes YAML as the primary path** — use Radius models first and only fall back to runtime-specific overrides when Radius cannot express the need.
- **Azure resource details in app service code** — keep those behind Dapr components and Radius recipes.
- **Environment intent scattered across ad hoc files** — keep it under `infra/radius/environments/`.

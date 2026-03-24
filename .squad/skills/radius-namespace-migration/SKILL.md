---
name: "radius-namespace-migration"
description: "Move between stock Applications.Core resources and preview Radius.Core/Compute types using first-party catalog evidence"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a Radius repo is deciding whether to stay on stock `Applications.Core/*` resources or pivot to newer `Radius.Core/*` / `Radius.Compute/*` names. The key question is not whether a future catalog might support the new namespace — it is whether the installed control plane and first-party docs prove that support today. This is especially useful when the catalog has moved only part of the resource surface and Dapr resources still live under `Applications.Dapr/*`. For repos with already-provisioned Dapr resources, treat application/environment identity continuity as a first-class migration constraint.

## Patterns

### Preserve app/environment identity when Dapr resources already exist

- If deployed `Applications.Dapr/*` resources already exist, keep the owning application/environment on `Applications.Core/applications` and `Applications.Core/environments` until Radius publishes a Dapr migration path that preserves ownership continuity.
- Existing Dapr resources are keyed to their application/environment IDs, not just their logical names. Repointing them to `Radius.Core/*` owners breaks idempotent updates for resources such as `statestore`, `pubsub`, and `platform-secrets`.
- You can still advance compute and ingress independently: `Applications.Core/containers` may move to `Radius.Compute/containers`, and `Applications.Core/gateways` may move to `Radius.Compute/routes`, while app/environment identity stays stable.

### Let live namespace rejection override speculative migrations

- If `rad deploy` fails with `InvalidResourceNamespace` for `Radius.Compute/containers`, stop treating `Radius.Compute/*` as a harmless schema-lag warning. The installed catalog does not support that surface.
- On stock Radius 0.55, revert app services to `Applications.Core/containers@2023-10-01-preview` and public ingress to `Applications.Core/gateways@2023-10-01-preview` unless your platform team can point to first-party docs or catalog metadata for the preview types in the target environment.
- Validate the rollback with two proofs together: official docs that still model containers/gateways under `Applications.Core/*`, and a clean `az bicep build` of `infra/radius/app.bicep` without `Radius.Compute/*` `BCP081` warnings.
- Keep the exact future pivot documented for later: `Applications.Core/containers` ↔ `Radius.Compute/containers` and `Applications.Core/gateways` ↔ `Radius.Compute/routes`, with the associated shape change from `properties.container` to `properties.containers[...]` and from `extensions[]` to `extensions.daprSidecar`.

### Treat post-revert runtime failures as a different layer

- After reverting to `Applications.Core/*`, use the next live `rad deploy` attempt to prove the namespace issue is gone. If Radius creates `Applications.Core/containers` resources for the affected services, the namespace fix is validated even if the deployment later stalls.
- If the next failure is Kubernetes runtime noise such as `ImagePullBackOff`, `ErrImagePull`, or registry `403 Forbidden`, do not reopen the namespace decision automatically. Hand off to whoever owns image publishing, tags, or registry authentication.
- For reviewer writeups, say both things plainly: the namespace regression is fixed, and the demo path can still be blocked by a separate workload issue.

### Migrate environments with recipe packs, not inline recipes

- Replace `Applications.Core/environments` with `Radius.Core/environments` only for fresh environments or explicit cutovers where recreating Dapr-owned resources is acceptable.
- Introduce a `Radius.Core/recipePacks` resource and move the old inline `recipes` map into `recipePack.properties.recipes`.
- If older files carry a single Azure provider scope string, decompose it into `subscriptionId` and `resourceGroupName` so the new environment schema can stay source-compatible with existing workflow inputs.

### Migrate compute resources as a shape change, not just a rename

- Replace `Applications.Core/applications` with `Radius.Core/applications` only when Dapr ownership continuity is not required (for example, fresh installs or planned re-creation of Dapr resources).
- Replace `Applications.Core/containers` with `Radius.Compute/containers`, converting `properties.container` into a `properties.containers` map keyed by the logical container name.
- Move Dapr wiring to `properties.extensions.daprSidecar`; keep existing connection wiring intact.
- Replace `Applications.Core/gateways` with `Radius.Compute/routes`, expressing the old path match as `rules[].matches[].httpPath` and target service as `destinationContainer`.

### Keep mixed namespaces explicit when the catalog is incomplete

- Leave `Applications.Dapr/*` in place when the active Radius catalog does not expose equivalent `Radius.*` Dapr resource types.
- When `Applications.Dapr/*` remains in place for existing estates, preserve `Applications.Core/*` application/environment ownership so repeated deploys remain idempotent.
- Require direct first-party evidence before approving any Dapr migration: the target `Radius.*` type should have its own official Radius schema/API docs, not just a conceptual mention on the generic Resource Types page.
- Treat official Radius Dapr authoring docs plus the Dapr schema/API reference as the source of truth for whether `stateStores`, `pubSubBrokers`, and `secretStores` are still expected to live under `Applications.Dapr/*`.
- Document any non-blocking schema lag, such as `BCP081` warnings from `az bicep build` for newly introduced `Radius.Compute/*` resources.
- Regenerate checked-in JSON artifacts immediately after migration so reviewers see the real compiled contract.

## Examples

- Application model: `infra/radius/app.bicep`
- Container module: `infra/radius/modules/container-service.bicep`
- Environment models: `infra/radius/environments/dev.bicep`, `infra/radius/environments/azure-radius.bicep`
- Operator docs: `docs/radius-validation-checklist.md`
- Stock-aligned gateway extraction: `docs/end-to-end-setup-walkthrough.md`

## Anti-Patterns

- Renaming every `Applications.*` resource blindly even when the installed catalog does not provide the new type.
- Migrating application/environment owners to `Radius.Core/*` while existing Dapr resources still live under `Applications.Dapr/*`; that breaks idempotent updates because the owning IDs change.
- Treating generic `Radius.*` resource-type concepts as proof that a specific Dapr resource now has a supported replacement.
- Treating `BCP081` warnings on `Radius.Compute/*` as acceptable after a live deployment has already failed with `InvalidResourceNamespace`.
- Porting `Applications.Core/environments` without introducing `Radius.Core/recipePacks`; the old inline recipe structure does not carry forward.
- Treating route hostname prefix hints as guaranteed behavior after moving to `Radius.Compute/routes`; the current route model leaves generated hostname selection to the active recipe.

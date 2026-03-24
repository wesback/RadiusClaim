---
name: "radius-namespace-migration"
description: "Safely migrate deprecated Applications.Core resources to Radius.Core and Radius.Compute while documenting mixed-catalog limits"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a Radius repo still declares `Applications.Core/*` environment, application, container, or gateway resources and the installed Radius catalog already exposes the newer `Radius.Core/*` and `Radius.Compute/*` replacements. This is especially useful when the catalog has moved only part of the resource surface and Dapr resources still live under `Applications.Dapr/*`.

## Patterns

### Migrate environments with recipe packs, not inline recipes

- Replace `Applications.Core/environments` with `Radius.Core/environments`.
- Introduce a `Radius.Core/recipePacks` resource and move the old inline `recipes` map into `recipePack.properties.recipes`.
- If older files carry a single Azure provider scope string, decompose it into `subscriptionId` and `resourceGroupName` so the new environment schema can stay source-compatible with existing workflow inputs.

### Migrate compute resources as a shape change, not just a rename

- Replace `Applications.Core/applications` with `Radius.Core/applications`.
- Replace `Applications.Core/containers` with `Radius.Compute/containers`, converting `properties.container` into a `properties.containers` map keyed by the logical container name.
- Move Dapr wiring to `properties.extensions.daprSidecar`; keep existing connection wiring intact.
- Replace `Applications.Core/gateways` with `Radius.Compute/routes`, expressing the old path match as `rules[].matches[].httpPath` and target service as `destinationContainer`.

### Keep mixed namespaces explicit when the catalog is incomplete

- Leave `Applications.Dapr/*` in place when the active Radius catalog does not expose equivalent `Radius.*` Dapr resource types.
- Require direct first-party evidence before approving any Dapr migration: the target `Radius.*` type should have its own official Radius schema/API docs, not just a conceptual mention on the generic Resource Types page.
- Treat official Radius Dapr authoring docs plus the Dapr schema/API reference as the source of truth for whether `stateStores`, `pubSubBrokers`, and `secretStores` are still expected to live under `Applications.Dapr/*`.
- Document any non-blocking schema lag, such as `BCP081` warnings from `az bicep build` for newly introduced `Radius.Compute/*` resources.
- Regenerate checked-in JSON artifacts immediately after migration so reviewers see the real compiled contract.

## Examples

- Application model: `infra/radius/app.bicep`
- Container module: `infra/radius/modules/container-service.bicep`
- Environment models: `infra/radius/environments/dev.bicep`, `infra/radius/environments/azure-radius.bicep`
- Operator docs: `docs/radius-validation-checklist.md`

## Anti-Patterns

- Renaming every `Applications.*` resource blindly even when the installed catalog does not provide the new type.
- Treating generic `Radius.*` resource-type concepts as proof that a specific Dapr resource now has a supported replacement.
- Porting `Applications.Core/environments` without introducing `Radius.Core/recipePacks`; the old inline recipe structure does not carry forward.
- Treating route hostname prefix hints as guaranteed behavior after moving to `Radius.Compute/routes`; the current route model leaves generated hostname selection to the active recipe.

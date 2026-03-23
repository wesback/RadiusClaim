---
name: "radius-first-aca-fallback"
description: "Pattern for making Radius the primary deployment contract while keeping an honest ACA fallback"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a repo wants a credible Radius-first deployment story on Azure, but Radius does not yet support the desired Azure compute target directly.

## Patterns

### Keep the app model deployable

- Put the `Applications.Core/applications` resource inside `infra/radius/app.bicep`.
- Let `rad deploy` inject the environment id.
- Pass only portable deployment parameters at deploy time (`containerRegistry`, `imageTag`, `deploymentTarget`).

### Split primary path from fallback path

- Default CI/CD to a Radius-first mode.
- Name the cloud-specific escape hatch explicitly (`aca-fallback`, not just `deploy`).
- Keep the fallback in the same workflow only when it serves a real platform gap.

### Isolate Azure specifics to the environment layer

- Register Azure-backed recipes in a dedicated Radius environment file (for example `infra/radius/environments/azure-radius.bicep`).
- Keep Dapr component names stable across Radius, local overlays, and app constants.
- Treat direct Azure bootstrap files as secondary artifacts, not the main application contract.

## Validation

- `az bicep build --file infra/radius/app.bicep`
- `az bicep build --file infra/radius/environments/azure-radius.bicep`
- `dotnet build CloudExpenseLite.slnx --nologo`
- `dotnet test CloudExpenseLite.slnx --nologo --no-build`

## Anti-Patterns

- Requiring the workflow to hand-craft per-service ACA YAML while still claiming Radius is orchestrating deployment.
- Leaving the fallback unnamed or undocumented so teams mistake it for the preferred path.
- Renaming Dapr components between local and cloud slices.

---
last_updated: 2026-03-23T17:50:00Z
---

# Graham History

## Phase 3 Work (2026-03-23)

### Delivered

**Phase 3 Pub/Sub Infrastructure**
- Added `infra/dapr/local/pubsub.yaml` — Redis-backed pub/sub component for local development
- Scoped access to `workflow-engine` and `notification-svc` only
- Reused existing local Redis container from Phase 2 (`localhost:6379`)
- No authentication required for local development
- No changes to `infra/dapr/local/docker-compose.yaml` (Redis already present)

### Design Decision

Kept pub/sub as a development overlay under `infra/dapr/local/`, preserving the pattern where Radius owns service topology while local overlays provide development-only Dapr components. This prevents Radius from needing to model local-only infrastructure and makes the distinction between production wiring and local emulation clear.

### Validation

- Component YAML validated by Karen as part of Phase 3 exit criteria
- Properly scoped to workflow-engine and notification-svc
- Reusing existing Redis simplifies local environment setup

## Learnings

- Keep Dapr component names aligned with shared contract constants (`statestore`, `pubsub`) in both Radius resources and local overlays so app code never needs environment-specific aliases.
- For local-only Dapr backing services, colocate the component YAML and the minimal emulator runtime under `infra/dapr/local/` so the override is obvious without competing with the Radius application model.

- Reuse the existing local Redis container for both Dapr state and pub/sub overlays unless a phase explicitly needs isolation; it keeps Phase 3 wiring explainable and avoids duplicate local infrastructure.

## Phase 5 Work (2026-03-23)

### Delivered

**Radius recipe-backed Azure slice**
- Renamed the Radius Dapr pub/sub resource to `pubsub` so the app contract, local overlay, and cloud model all use the same component name.
- Added recipe-backed Dapr resource wiring in `infra/radius/app.bicep` for `statestore`, `pubsub`, and `platform-secrets` with deterministic Azure resource naming.
- Created `infra/radius/environments/dev.bicep` to register Azure-backed recipes against the local Kubernetes development environment.
- Replaced all placeholder Azure recipe files with real Bicep implementations for Blob Storage state, Service Bus pub/sub, and Key Vault secrets.
- Updated `infra/radius/environments/dev.parameters.json` so the dev slice reports `deploymentTarget=local` instead of ACA.

### Validation

- `az bicep build --file infra/radius/app.bicep` ✅
- `az bicep build --file infra/radius/environments/dev.bicep` ✅
- `az bicep build --file infra/radius/recipes/azure/state-store.bicep` ✅
- `az bicep build --file infra/radius/recipes/azure/pubsub.bicep` ✅
- `az bicep build --file infra/radius/recipes/azure/secrets.bicep` ✅
- `dotnet build CloudExpenseLite.slnx --nologo` ✅
- `dotnet test CloudExpenseLite.slnx --nologo --no-build` ✅
- `rad` CLI local validation remains blocked in this environment because `rad` is not installed.

#### Learnings

- Radius environment files tell the platform story best when they register named recipes explicitly instead of leaning on default recipe indirection; it keeps the operator handoff teachable.
- For Azure-backed Dapr resources, deterministic names passed from the app model into recipe parameters keep the component contract readable while leaving the provisioning logic inside the recipe.
- When secrets consumption is deferred, model the Dapr secret store honestly as plumbing only; avoid pretending app-side secret reads are part of the same phase.
- Make `infra/radius/app.bicep` self-contained by declaring `Applications.Core/applications` inside the app model; `rad deploy` should inject the environment, not depend on a caller-supplied application id.
- When Radius lacks a first-party compute target (here: Azure Container Apps), keep the Radius-first workflow primary and name the escape hatch explicitly as a fallback rather than letting imperative deployment become the default story.
- Key Radius-first Azure files: `infra/radius/app.bicep`, `infra/radius/environments/azure-radius.bicep`, `infra/radius/environments/azure-radius.parameters.json`, and `.github/workflows/deploy-azure.yml`.

## Radius-First Redesign Work (2026-03-23)

### Delivered

**Radius-First Azure Deployment Path**
- Restructured `.github/workflows/deploy-azure.yml` to default to `deployment_mode=radius-first`
- Created `infra/radius/environments/azure-radius.bicep` as primary Radius environment
- Split Azure resources between bootstrap (ACR, ACA env, identity, Log Analytics) and Radius-driven (app services, Dapr components, backing resources via recipes)
- Dapr component names (`statestore`, `pubsub`, `platform-secrets`) remain stable across all paths
- ACA fallback explicitly demoted with conditional job and honest documentation of Radius compute gap

### Design Decision

Kubernetes-based Radius path with Azure recipe support is stronger story than trying to bootstrap ACA for Radius. Radius as primary orchestrator, Azure CLI as explicit fallback for when ACA compute support arrives.

### Validation

- All Bicep files parse cleanly (app.bicep, azure-radius.bicep, three recipes)
- `dotnet build` and `dotnet test` pass with zero changes to app code
- Workflow structure separates Radius path (primary) from ACA path (secondary) clearly
- Karen approved all acceptance criteria

## Learnings (Phase 7+)

- The Radius-first pattern succeeded because we made the Azure bootstrap honest: it creates substrate only, not deployment.
- When a tool lacks first-party support for a compute target, making the fallback explicit and clearly secondary protects the primary tool's credibility story.
- Parameterizing Dapr component types in the app model (`daprBackings`) while keeping logical names stable (`statestore`) is the right balance for portability without sacrificing demo clarity.
- Next team: If you need ACA support in Radius, a clean migration exists because this path separated bootstrap from deployment.

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

## Phase 7 Work (2026-03-24)

### Delivered

**Phase 7 Platform Validation Lane**
- Created comprehensive `docs/radius-validation-checklist.md` covering pre-deployment validation, Bicep validation, deployment steps, post-deployment validation, troubleshooting, and known gaps
- Enhanced README secrets/variables documentation with clear Radius-first vs ACA-fallback requirements table
- Added "Additional Documentation" section to README with links to demo walkthrough, validation checklist, and ADR
- Validated all Bicep files parse cleanly (app.bicep, azure-radius.bicep, azure.bicep, all three recipes)
- Validated solution builds and tests pass (zero warnings, zero errors)
- Documented honest gaps: end-to-end validation requires live Radius environment (not available here); structural validation complete

### Design Decision

Kept the Radius-first story intact while making validation requirements explicit and accessible. The validation checklist tells operators exactly what to check before deploying, what success looks like, and how to troubleshoot — without pretending we can run end-to-end flows in this environment. The honesty about what requires a live environment is more credible than faking validation.

### Validation

- ✅ `az bicep build --file infra/radius/app.bicep`
- ✅ `az bicep build --file infra/radius/environments/azure-radius.bicep`
- ✅ `az bicep build --file infra/radius/environments/azure.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/*.bicep` (all three)
- ✅ `dotnet build CloudExpenseLite.slnx --configuration Release` (zero warnings)
- ✅ `dotnet test CloudExpenseLite.slnx --configuration Release` (all passing)
- ✅ README documentation updated with secrets/variables clarity
- ✅ Comprehensive validation checklist created for Radius-first path
- ⚠️ End-to-end validation against live Radius environment: documented as requiring live cluster (honest gap)

### Phase 7 Status

**Platform validation lane: COMPLETE**
- Structural validation done (Bicep parse, build, test)
- Documentation complete (validation checklist, secrets/variables clarity)
- Known gaps documented honestly (live environment needed for end-to-end validation)
- No platform redesign (Radius-first pattern intact)
- No workflow changes (existing deploy-azure.yml remains authoritative)

**Remaining Phase 7 work (Eddie's lane):**
- Demo walkthrough already exists (`docs/phase-7-demo-walkthrough.md`)
- ADR already exists (`docs/ADR-0001-azure-cli-fallback.md`)
- Integration test suite noted as "future enhancement" (not blocking)

## Learnings (Phase 7)

- Platform validation documentation should separate "what you can verify now" (Bicep parse, builds, structural checks) from "what requires live deployment" (end-to-end flows) — mixing them creates false confidence or forces teams to fake validation.
- When documenting secrets/variables for dual-path workflows, use a table that clearly shows which path requires which config — reduces setup errors and eliminates guesswork about which variables to set.
- Validation checklists become more valuable when they include troubleshooting steps and known gaps — they tell the next team what's normal vs. what's broken.
- The "Additional Documentation" section in README acts as a navigation hub for deeper content without bloating the main README — keeps the ten-minute story accessible while making validation/ADR discoverable.

### 2026-03-24: Phase 7 Platform Validation Lane Complete

**Deliverables:**
1. **docs/radius-validation-checklist.md**
   - Pre-deployment validation (Radius CLI, Kubernetes, Azure provider, secrets/variables)
   - Bicep validation for all platform files
   - Step-by-step deployment instructions
   - Post-deployment validation (pod health, Dapr components, Azure resources)
   - Troubleshooting guide for common issues
   - Known gaps documented honestly (live environment needed)

2. **README.md Enhancements**
   - Secrets/variables table with Radius-first vs ACA-fallback requirements
   - "Additional Documentation" section linking to validation checklist, demo walkthrough, ADR
   - Phase 7 status updated

3. **Structural Validation**
   - All Bicep files parse cleanly (az bicep build)
   - Solution builds zero warnings (dotnet build)
   - All tests pass (dotnet test)

**What This Enables:**
- Platform engineers have clear deployment checklist
- Secrets/variables requirements explicit and unambiguous
- Troubleshooting guidance for common failures
- Known gaps documented honestly

**What Remains (Non-Blocking):**
- Live end-to-end validation (requires deployed Radius environment)
- CI/CD end-to-end validation (add when live environment available)

**Status:** COMPLETE — Platform validation lane finalized

## Learnings

- Closing the Radius CI gap worked best by reusing the shared flow-validation script and collecting runtime-specific evidence separately: `kubectl port-forward`/`kubectl logs` for Radius, runtime-native commands for other targets.
- When a validation script also emits a small machine-readable artifact (expense IDs, correlation IDs, summary counts), CI can prove downstream pub/sub evidence without duplicating the flow logic.

## .gitignore Housekeeping (2026-03-24)

**Updated `.gitignore`**
- Preserved all existing `.squad/` ignore rules (orchestration-log, log, decisions/inbox, sessions, .squad-workstream)
- Added .NET conventional ignores: `bin/`, `obj/`, `*.exe`, `*.dll`, `*.pdb`
- Added IDE ignores: `.vs/`, `.vscode/`, `*.user`, `*.suo`, `*.sln.iml`, `.idea/`
- Added NuGet ignores: `*.nupkg`, `*.snupkg`, `.nuget/`
- Added test/coverage ignores: `TestResults/`, `coverage/`, `*.trx`
- Added OS ignores: `.DS_Store`, `Thumbs.db`

**Rationale:** .NET projects accumulate build debris (bin, obj) that had been going into the index. A conventional .gitignore keeps `git status` clean and prevents accidental commits of development-environment-specific files (IDE configs, nuget caches, test results). Pattern order: Squad state → .NET build → IDE → NuGet → test/coverage → Rider → OS.

**Validation:** .gitignore active; git now cleaning up previously-tracked build artifacts (bin/, obj/ deletions detected in status).

## Phase 7 Completion (2026-03-24)

### Orchestration Log Published
- Session date: 2026-03-24T09:11:24Z
- Documented CI validation gap closure
- Confirmed non-blocking live Radius validation item
- Filed orchestration-log/20260324T091124Z-graham.md

### Decision Merged to Squad Records
- Graham — Radius CI validation path decision added to squad/decisions.md
- Captures port-forward pattern and script reuse as core pattern for distributed validation
- Committed to squad records as reference for future deployments

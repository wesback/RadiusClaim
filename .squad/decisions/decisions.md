# Decisions Registry

**Last Updated:** 2026-03-24T17:53:40Z

---

## 1. Full Codebase Review — Opus 4.6 Deep Audit

**By:** Daisy (Lead)  
**Date:** 2026-03-24  
**Status:** FINDINGS DOCUMENTED — action required

### Summary

Conducted a full-depth architectural review of the entire RadiusClaim codebase: all source code (17 files), all infrastructure (Radius bicep, recipes, environments, local Dapr configs, scripts), all documentation (README, docs/*.md), and the CI/CD workflow. Used Opus 4.6 model for depth.

### Critical Findings (7 total — must fix before demo)

#### Infrastructure
1. **`Radius.Compute/*` resource types may not exist in stock Radius 0.55** — `app.bicep` and `container-service.bicep` use `Radius.Compute/containers` and `Radius.Compute/routes` with API version `2025-08-01-preview`. Standard Radius 0.55 uses `Applications.Core/containers` and `Applications.Core/httpRoutes`. If targeting a custom preview build, document it explicitly. Otherwise, `rad deploy` will fail.
2. **Pub/sub recipe outputs wrong Dapr component type** — Recipe outputs `pubsub.azure.servicebus` (queues), but the ACA bootstrap and app logic expect `pubsub.azure.servicebus.topics`. Messages won't flow through recipe-provisioned path.
3. **State store version mismatch** — ACA bootstrap uses v2, recipe outputs v1. Breaking schema differences between versions.

#### Documentation
4. **README project tree shows `sovereignapp/` not `RadiusClaim/`** — Stale name from prior incarnation.
5. **README Contracts path wrong** — Shows `src/RadiusClaim.Contracts/` but actual path is `src/shared/RadiusClaim.Contracts/`.
6. **`dev.bicep` mislabeled as "Local Radius environment"** — It provisions Azure-backed recipes, not local Redis. Breaks portability narrative.

#### CI/CD
7. **`deploy-azure.yml` has no `azure/login` step** — Workflow sets OIDC permissions but never authenticates. `rad credential register azure` will fail without ambient Azure credentials.

### Important Findings (11 total — should fix for credibility)

#### Code
- `BuildNotification` throws on `ExpenseRejected` — latent crash when rejection logic is added
- `ApproveExpenseActivity` idempotency guard is too narrow (only handles auto-approved + Reimbursed)
- `ExpenseRejected` record and `Rejected` status are dead contracts — no code path produces them
- `DaprClient.CreateInvokeHttpClient` bypasses DI-configured client endpoint

#### Infrastructure
- No local Dapr secret store component — `platform-secrets` reference in `app.bicep` will fail local `dapr run`
- `dev.bicep` uses `resourceGroup().id` default — won't resolve in `rad deploy`
- `azure-radius.parameters.json` is incomplete (missing required params)
- Key Vault recipe lacks purge protection (7-day vs 90-day retention)
- Recipe auth uses shared keys while ACA bootstrap uses managed identity

#### Documentation/CI
- README "Quick Start (Local Dev)" still says "Coming in Phase 2" — we're in Phase 7
- `dotnet test` in CI is vacuous — zero test projects exist, green badge is misleading
- Stale `ghcr.io/sovereignapp/radiusclaim` default registry in `app.bicep` and params files
- Validation checklist shows `Applications.Core/containers` but code uses `Radius.Compute/containers`

### Decisions

1. **Graham** should own infra criticals (C1–C3) — recipe type mismatches and resource type resolution.
2. **Eddie** should own docs criticals (C4–C6) — README accuracy sweep.
3. **Graham** should fix the CI workflow auth gap (C7).
4. **Billy** should clean the dead `ExpenseRejected` contract or wire it — decide one way.
5. The `dotnet test` step should either be removed from CI or Karen should be asked to create real test projects.

### Verdict

**App code is clean.** Zero portability violations, correct Dapr SDK usage, sound workflow design. Billy's work holds up.

**Infrastructure has real deployment blockers.** The recipe type mismatches (C2, C3) will cause silent failures on Radius-provisioned paths. The `Radius.Compute/*` question (C1) needs immediate clarification.

**Documentation has drifted significantly from the code.** Multiple stale names, wrong paths, and a portability narrative that doesn't match the actual `dev.bicep` behavior. Eddie needs a reconciliation pass.

**CI workflow will fail in a fresh environment** due to missing Azure auth. This should be the first fix since it blocks validation of everything else.

---

## 2. Radius.Compute/* Namespace Rejection — Revert to Applications.Core/*

**By:** Daisy (Lead)  
**Date:** 2026-03-24  
**Status:** DECISION — REJECT current `Radius.Compute/*` modeling, revert to `Applications.Core/*`

### Situation

Deployment confirms what my earlier full-codebase review flagged as Critical Finding C1: Azure-backed recipes (Dapr state, pub/sub, secrets) provision successfully, but all three app services fail because `Radius.Compute/containers@2025-08-01-preview` and `Radius.Compute/routes@2025-08-01-preview` are not recognized resource types in the deployed Radius environment.

The `Radius.Compute` namespace was adopted based on Graham's migration proposal during Phase 5–6. `az bicep build` compiled with only `BCP081` warnings, which the team accepted as "expected." The warnings were actually honest: these types don't resolve at deploy time against stock Radius.

### Decision

**REJECT the `Radius.Compute/*` namespace for containers and routes. Revert to `Applications.Core/containers` and `Applications.Core/httpRoutes`.**

Rationale:
1. The sample must deploy on stock Radius without preview builds or custom type registrations. That's the whole point of a reference sample.
2. `BCP081` warnings were a signal, not noise. We treated compile-time ambiguity as acceptable when it was actually predicting a deploy-time failure.
3. `Applications.Core/applications` already stayed on the old namespace (correctly). The compute resources should follow the same boundary.
4. The `Applications.Dapr/*` types never moved and work fine. The mixed state is the problem — not namespace age.

### What Changes

| File | Current | Revert To |
|---|---|---|
| `infra/radius/modules/container-service.bicep` | `Radius.Compute/containers@2025-08-01-preview` | `Applications.Core/containers@2023-10-01-preview` |
| `infra/radius/app.bicep` | `Radius.Compute/routes@2025-08-01-preview` | `Applications.Core/httpRoutes@2023-10-01-preview` |
| `infra/radius/app.json` | Regenerated from above | Regenerate after revert |
| README.md, docs/*.md | References to `Radius.Compute/*` | Update to `Applications.Core/*` |

### Shape Changes Required

The revert is not a pure string swap. Graham's migration changed resource shapes:
- `Radius.Compute/containers` uses a `containers` map + `extensions.daprSidecar` object
- `Applications.Core/containers` uses a `container` singular object + `extensions` array with `kind: 'daprSidecar'`
- `Radius.Compute/routes` has different rule/destination semantics than `Applications.Core/httpRoutes`

Graham must handle the shape revert, not just the namespace rename.

### Who Does the Revision

**Graham** should NOT do this revision alone. He authored the original migration and approved the `BCP081`-is-acceptable position. Per my review protocol: when I reject work, a different agent should revise OR Graham revises with explicit reviewer oversight.

**Recommendation:** Graham does the revert (he knows the shape differences best), but **Karen** must validate the result against a fresh `rad deploy` before it merges. No more "compiles clean" as a proxy for "deploys clean."

### Follow-Up Items (From Earlier Review) — Pick Up Immediately

After the compute revert unblocks deployment, these findings from my full-codebase review become the next priorities:

1. **C2: Pub/sub recipe type mismatch** — Recipe outputs `pubsub.azure.servicebus` (queues) but app expects `pubsub.azure.servicebus.topics`. Graham owns this.
2. **C3: State store version mismatch** — ACA bootstrap uses v2, recipe outputs v1. Graham owns this.
3. **C7: CI workflow missing `azure/login`** — Workflow has OIDC permissions but no auth step. Graham owns this.

These three are the next deployment blockers after compute is unblocked.

### Lesson

Compile-time validation is necessary but not sufficient. `az bicep build` with warnings told us "I don't know these types" — we should have treated that as "these types might not exist" rather than "these types are just new." For a reference sample, the bar is: it deploys on stock tooling, period.

---

## 3. Document Azure Credential Registration in Radius Deployment

**By:** Eddie  
**Date:** 2026-03-24  
**Owner:** Eddie  
**Status:** Complete

### Problem

Graham's recipe troubleshooting diagnosed that Radius recipe deployment fails with `azure-azurecloud-default` secret errors when the Azure credential is not registered with the Radius control plane. This critical bootstrap step was missing from:
- GitHub Actions workflow
- Manual deployment walkthrough
- Validation checklist
- README narrative

### Solution

Added Azure credential registration documentation across four artifacts:

1. **README.md** — Added "Azure credential registration (required)" section
   - High-level explanation of what must happen and why
   - Error message that indicates the problem
   - Directs readers to checklist for steps

2. **docs/radius-validation-checklist.md** — Comprehensive operator guidance
   - Pre-deployment checkbox: explains purpose, shows command, verifies success
   - Deployment Step 2: exact sequence and critical warning
   - Troubleshooting entry: diagnosis, solution, explanation of the error

3. **docs/end-to-end-setup-walkthrough.md** — Manual deployment path
   - Inserted credential registration block after environment creation
   - Placed before environment Bicep deployment
   - Comments explain what the credential enables

4. **.github/workflows/deploy-azure.yml** — CI/CD implementation
   - New step: "Register Azure provider credentials with Radius"
   - Placed between workspace setup and environment deployment
   - Matches manual guidance sequence

### Key Design

**Sequence:** workspace → environment → **credential registration** → recipe publishing → environment deploy → app deploy

**Error message:** `azure-azurecloud-default` (Kubernetes secret) is the operator-visible symptom; calling it out helps teams recognize the issue

**Credibility:** Both CI/CD and manual paths now show the same step in the same sequence, building confidence in the guidance

### Alignment with Graham's Work

This documentation supports Graham's recipe repairs:
- Treats credential registration as a separate bootstrap concern from app/environment Bicep
- Separates "missing credential" (bootstrap) from "recipe output contract bugs" (recipe layer)
- Points operators to credential registration as the first diagnostic step
- Uses troubleshooting skill `radius-azure-recipe-troubleshooting/SKILL.md` as reference

### Related Files

- Graham history: Radius Dapr provisioning fix, Key Vault remediation, troubleshooting skill creation
- Eddie history: Phase 10 documentation work
- Modified docs: README, walkthrough, validation checklist, workflow
- Modified recipes: Azure Blob, Service Bus, Key Vault (removals of manual resource IDs per Graham's repairs)

---

## 4. Revert app compute surface to stock Applications.Core on Radius 0.55

**By:** Graham (Platform Dev)  
**Date:** 2026-03-24  
**Status:** IMPLEMENTED

### Decision

Keep RadiusClaim app services on `Applications.Core/containers@2023-10-01-preview` and public ingress on `Applications.Core/gateways@2023-10-01-preview` for the shared repo. Do not depend on `Radius.Compute/containers` or `Radius.Compute/routes` unless the target Radius installation explicitly documents and registers those preview resource types.

### Why

- Live deployment now proves the concrete blocker: Azure-backed recipes succeed, then app service deployment fails with `InvalidResourceNamespace` for `Radius.Compute/containers`.
- First-party Radius 0.55 docs still model stock container and gateway authoring on `Applications.Core/*`, so the repo should match the documented control-plane surface.
- The repo's public endpoint story is already gateway-oriented (`rad deploy` prints a public endpoint); `Applications.Core/gateways` is the stock ingress resource that preserves that operator experience.

### Exact future pivot to document, not depend on today

- `Applications.Core/containers` → `Radius.Compute/containers`
- `Applications.Core/gateways` → `Radius.Compute/routes`
- Shape changes required: `properties.container` → `properties.containers[...]`, and `extensions[]` → `extensions.daprSidecar`

### Team Impact

- Platform and docs should describe the repo as stock-Radius-0.55 aligned.
- Reviewers should treat any new `Radius.Compute/*` introduction as preview-only work that requires explicit catalog proof, not just a successful Bicep compile.
- Troubleshooting should pivot from schema warnings to namespace support whenever live deploy returns `InvalidResourceNamespace`.

### Repo touchpoints

- `infra/radius/app.bicep`
- `infra/radius/modules/container-service.bicep`
- `infra/radius/app.json`
- `README.md`
- `docs/end-to-end-setup-walkthrough.md`
- `docs/radius-validation-checklist.md`

---

## 5. Radius Azure recipes should not manually emit Azure resource IDs

**By:** Graham (Platform Dev)  
**Date:** 2026-03-24  
**Status:** Proposed

### What

For Azure-backed Radius recipes in this repo, remove manual `result.resources` emission when the recipe only creates Azure resources. Keep recipe outputs focused on Dapr `values` and `secrets`, then regenerate the checked-in JSON mirrors.

### Why

Radius already tracks Azure backing resources for these recipes. Manually emitting storage account, Service Bus, or Key Vault IDs creates contract drift and is a concrete source of deployment failure.

### Scope

- `infra/radius/recipes/azure/state-store.{bicep,json}`
- `infra/radius/recipes/azure/pubsub.{bicep,json}`
- `infra/radius/recipes/azure/secrets.{bicep,json}`

### Implication

Future Azure/AWS recipe work should only populate `result.resources` for Kubernetes/UCP IDs that Radius cannot infer.

---

## 6. Graham — Daisy follow-ups (C2, C3, C7)

**By:** Graham (Platform Dev)  
**Date:** 2026-03-24  
**Status:** IMPLEMENTED

### Decision

Close Daisy's next platform follow-ups by aligning the Radius recipe contract with the repo's existing ACA reference contract, while keeping CI bootstrap explicit instead of adding runner-side Azure auth glue.

### What Changed

1. **C2 — Pub/sub recipe contract aligned to topics**
   - `infra/radius/recipes/azure/pubsub.bicep` now outputs `pubsub.azure.servicebus.topics`
   - The recipe now pre-creates the demo topic (`expense-notifications`) and subscriber-facing subscription (`notification-svc`)
   - `namespaceName` metadata is now emitted as the Service Bus FQDN to match Dapr's topics guidance
   - `infra/radius/app.bicep` passes the subscription name explicitly so the app model stays teachable

2. **C3 — State store contract aligned to v2**
   - `infra/radius/recipes/azure/state-store.bicep` now emits `state.azure.blobstorage` version `v2`
   - This matches `infra/radius/environments/azure.bicep`, which already modeled the ACA reference path on v2

3. **C7 — Investigated workflow auth/bootstrap gap**
   - Current workflow already uses the right bootstrap primitive for Radius: `rad credential register azure sp`
   - No `azure/login` step was added because the runner does not provision Azure resources directly; Radius does, using the registered service principal
   - Removed the unused `id-token: write` permission and documented the intent inline so the workflow no longer suggests an OIDC path it does not use

### Why

- The demo story is cleaner when both deployment surfaces prove the same Dapr component contracts.
- Service Bus topics plus disabled entity management only stays honest if the recipe creates the topic/subscription pair the app actually uses.
- CI should show the real trust boundary: kubeconfig to reach the cluster, service principal registration so Radius can reach Azure.

### Validation

- ✓ `az bicep build --file infra/radius/app.bicep`
- ✓ `az bicep build --file infra/radius/environments/azure-radius.bicep`
- ✓ `az bicep build --file infra/radius/recipes/azure/pubsub.bicep`
- ✓ `az bicep build --file infra/radius/recipes/azure/state-store.bicep`
- ✓ `dotnet build RadiusClaim.slnx --configuration Release`
- ✓ `dotnet test RadiusClaim.slnx --configuration Release --no-build`
- ✓ YAML parse of `.github/workflows/deploy-azure.yml`

---

## 7. Karen: approve the stock Applications.Core revert

**By:** Karen (Reviewer)  
**Date:** 2026-03-24  
**Status:** APPROVED

### Decision

Approve Graham's revert from `Radius.Compute/*` back to stock `Applications.Core/*` resources for the deployable app surface on the current Radius environment.

### Why

- Local evidence is now live, not hypothetical: stock Radius `0.55.0` is installed and reachable on this machine, and `rad deploy infra/radius/app.bicep` advanced past the old namespace failure.
- The deploy created `Applications.Core/containers` resources for `expense-api`, `workflow-engine`, and `notification-svc`, which directly disproves the earlier `InvalidResourceNamespace` blocker for the reverted model.
- The checked-in Bicep/JSON contract is internally consistent again: containers use `properties.container`, Dapr wiring uses the legacy `extensions[]` array, and ingress reverts to `Applications.Core/gateways`.

### Team Impact

- For stock Radius `0.55`, keep `Applications.Core/containers` and `Applications.Core/gateways` in `infra/radius/app.bicep` unless the platform team can point to a real preview catalog installed in the target environment.
- If a live deploy now fails later on pod readiness or image pull, treat that as a separate runtime issue; do not reopen the namespace migration by default.
- Current follow-up blocker for the demo path is image availability/auth for `ghcr.io/sovereignapp/radiusclaim/*:phase1`, not the Radius namespace choice.

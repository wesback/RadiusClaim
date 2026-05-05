---
last_updated: 2026-05-05T08:58:18Z
status: archived_2026-05-05
---

# Graham History (Summarized)

**Role:** Platform Dev — infrastructure, Radius, Dapr, recipes, CI/CD.

## Key Decisions

### Phase 7 Radius Redesign
- Split Azure bootstrap (ARM Bicep) from Radius app deployment (`rad deploy`)
- Recipe wiring in `app.bicep` → `templatePath` to OCI artifacts → registry-based resolution at deploy time
- Implemented Radius.Compute → Applications.Core revert per Daisy's critical review
- Shape changes: `containers` map → singular `container`, `extensions.daprSidecar` → `extensions[]` array

### Portability Audit (2026-04-03)
- ✅ PASS — Application code has ZERO direct Azure SDK coupling
- ✅ PASS — All integration flows through Dapr components only
- ✅ PASS — Dapr Workflows portable to any orchestrator (Kubernetes-agnostic)
- ✅ PASS — Recipes properly wired in bicep (no hardcoded URLs)
- **Verdict:** FULLY REALIZED — Production ready

### Environment Deployment Parameter Fix (2026-04-03)
- Fixed environment.parameters.json to include `recipeInputs` with correct key-value structure
- All template files clean Bicep validation, no warnings

### Security Review & .gitignore (2026-04-02)
- Removed sensitive data and build artifacts from tracking
- Added `.gitignore` patterns for generated files and credentials

### App-Modeling Portability (2026-05-05)
- Integrated `app-modeling` skill properly with directory-based filtering
- No model/script/doc drift; app definition reflects actual resource state

## Current Status

All portability pillars validated. Application ready for showcase and multi-cloud deployment patterns.

**Full history archived to `.squad/agents/graham/history-archive.md`**

## Learnings

- 2026-06-13 — `docs/blog/portability.md` still reflects an older repo shape in several high-risk places: it says Radius auto-configures Dapr components, shows Azure Blob Storage as the Azure state store, and presents `infra/radius/environments/local.bicep` / `infra/radius/recipes/local/` as a ready portability path. The current repo contract is PostgreSQL + Service Bus + Key Vault for Azure, explicit post-deploy Dapr component projection via `scripts/apply-dapr-components-from-recipes.sh`, and a local Radius environment that is only an experimental placeholder.
- 2026-05-05 — Reviewer gate re-check: the updated `docs/blog/portability.md` now matches the repo's current platform contract closely enough to approve. The post stays honest about PostgreSQL + Service Bus + Key Vault on Azure, the explicit Dapr component projection step after `rad deploy`, the Kubernetes-first deployment story, and `infra/radius/environments/local.bicep` remaining an experimental placeholder rather than a supported local Radius path.

## Blog Review Work (2026-05-05)

**Task:** Review docs/blog/portability.md for technical and factual accuracy against the current repo  
**Outcome:** Authored "Graham Decision — Portability blog must match the supported repo contract" (2026-06-13)  
**Key Findings:**
  - Blob Storage reference is outdated (should be PostgreSQL)
  - Auto-component-projection claim is false (requires explicit post-deploy step)
  - Local Radius path presented as ready when only an experimental placeholder
  - Gateway access not guaranteed; port-forward is deterministic path
**Impact:** Blog remediation work now has clear factual acceptance criteria.

## Portability Blog Technical Gate Work (2026-05-05, Session T13:10Z)

**Task (graham-6):** Technical accuracy gate for portability blog — APPROVE.  
**Outcome:** ✓ APPROVE as technically accurate against current repo.  
**Decision Made:** "Graham Decision — portability blog technical accuracy gate"  
**Validation:** Azure services correct (PostgreSQL, Service Bus, Key Vault); Dapr projection explicit post-deploy step; Kubernetes-first with AKS example; local dev via `infra/dapr/local`; endpoint access honest about cluster dependency.  
**Impact:** Combined with Eddie's rewrite (eddie-1) and Daisy's architecture gate (daisy-4), portability blog now passes full approval cycle with guardrails for future maintenance.

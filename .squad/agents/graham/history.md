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

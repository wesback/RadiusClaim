# Eddie: Documentation Update — Verified Deployment Cycle

**Date:** 2026-04-06T00:00:00Z
**Author:** Eddie (Docs/Story)
**Status:** Complete

## What Changed

Updated four documentation files to reflect the verified end-to-end deployment cycle that Rod successfully ran (teardown → prepare-cluster → bootstrap → validate).

### README.md
- Added "Verified Deployment Cycle" section with the exact tested command sequence
- Added success criteria table (pod READY counts, Dapr component names, smoke test pass)
- Added "Known Platform Behaviours" block documenting the component projection gap, recipe output opacity, gateway readiness lag, and CI vs local auth mode differences
- Replaced stale "no backfill needed / bootstrap is orchestration-only" claim with accurate two-phase description
- Fixed "Coming in Phase 2" local dev placeholder with working docker-compose + dapr run commands
- Clarified `AZURE_CLIENT_SECRET` secrets table entry: CI uses SP mode; local bootstrap defaults to workload identity
- Updated project status footer to "End-to-end deployment validated ✅"

### docs/end-to-end-setup-walkthrough.md
- Retitled Step 9a from "Verify and Backfill Dapr Components" to "Verify Dapr Components (bootstrap) / Apply Components (manual path)"
- Added routing note at top: bootstrap path is automatic; step only required for manual `rad deploy` path or bootstrap failure recovery
- Replaced deprecated `deploy-dapr-components-workload-identity.sh` with `apply-dapr-components-from-recipes.sh` and updated parameter signatures

### docs/radius-validation-checklist.md
- Fixed "zero-secrets model" CI claim: CI workflow actually uses `AZURE_CLIENT_SECRET` for SP registration
- Updated Step 5a to use `apply-dapr-components-from-recipes.sh` with correct parameters
- Fixed three troubleshooting references to old script

### PHASE3_INTEGRATION_VALIDATION.md
- Added historical note banner explaining where the Phase 3 design diverged from actual implementation (Radius does not project Dapr CRDs from recipes; `apply-dapr-components-from-recipes.sh` is the real mechanism)

## Why These Changes

The previous documentation claimed bootstrap was "orchestration-only" and that Dapr components were "created declaratively in recipes — no backfill needed." This was inaccurate. `bootstrap.sh` runs a two-phase process where Phase 2 creates Kubernetes `components.dapr.io` CRDs by parsing Azure resource IDs from `status.outputResources[]`. The contradiction between docs and code was the highest-credibility-risk issue in the doc set.

The stale script reference (`deploy-dapr-components-workload-identity.sh`) in the checklist would send operators to a deprecated tool. Fixed to point to the canonical `apply-dapr-components-from-recipes.sh`.

## What Users Should Know

1. **The verified deployment sequence is:** `teardown.sh` → `prepare-cluster.sh` → `bootstrap.sh` → `validate-deployment.sh`
2. **"Success" is specific:** 3 deployments each 2/2 Running, three `components.dapr.io` objects present, smoke test passing
3. **Dapr component creation is automated in bootstrap** but NOT in manual `rad deploy` paths — use `apply-dapr-components-from-recipes.sh` manually in that case
4. **CI uses service principal mode** (`AZURE_CLIENT_SECRET` required); local bootstrap defaults to workload identity
5. **The component projection gap is a known Radius platform behaviour**, not a sample bug

## Coordination Note

Rod's recipe refactor (recipes creating CRDs directly) is not yet complete. When that lands, the "two-phase bootstrap" description and the `apply-dapr-components-from-recipes.sh` workaround documentation should be revisited. The "Known Platform Behaviours" section in README is the right place to update when that changes.

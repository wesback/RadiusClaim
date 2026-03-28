# Orchestration Log: Daisy — Portability Audit

**Date:** 2026-03-26  
**Agent:** Daisy (Researcher)  
**Task:** Portability audit of 6 bootstrap fixes applied in live debugging session  
**Status:** COMPLETE

## Outcome

- ✅ 6 fixes analyzed for Dapr/Radius portability impact
- ✅ 3 items requiring decisions identified: GHCR pull secret conditional, SPN scope narrowing, local dev recipes
- ✅ No portability regressions found; abstraction layers intact
- ✅ Inbox decision file: `.squad/decisions/inbox/daisy-portability-audit.md`

## Summary

All 6 fixes maintain cloud-agnostic abstraction:
- Fix #1–2: SP credential handling — ✅ Clean
- Fix #3: RBAC — ⚠️ Minor (subscription scope should narrow to RG)
- Fix #4: Radius API version — ✅ Clean
- Fix #5–6: Pull secret timing + ACR — ⚠️ Minor (make conditional on registry type)

App code remains cloud-agnostic; scripts are appropriately Azure-specific.

## Decisions for Team

1. **GHCR Pull Secret (Highest Priority):** Make `ghcrImagePullRef` conditional on registry type
   - If `CONTAINER_REGISTRY` starts with `ghcr.io`, create secret + pass ref
   - If ACR or native auth, skip secret + pass empty ref
   - Rename to `imagePullSecretRef` for registry-neutrality

2. **SPN Scope (Medium Priority):** Narrow `prepare-cluster.sh` Contributor role to resource group
   - Change: `--scopes /subscriptions/$ID` → `--scopes /subscriptions/$ID/resourceGroups/$RG`
   - Requires RG to exist first (already ensured)

3. **Local Dev Recipes (Future Work):** Create `infra/radius/recipes/local/` with Redis, RabbitMQ, file-based secrets
   - Completes "swap recipes" portability promise in architecture docs
   - Enables genuine local dev without Azure dependencies

## Files Generated

- `.squad/decisions/inbox/daisy-portability-audit.md` — 218-line decision document

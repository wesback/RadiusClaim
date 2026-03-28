# Session Log: Radius.Compute Review & Revert

**Date:** 2026-03-24  
**Timestamp:** 2026-03-24T17:36:38Z

## Summary

Live Radius deployment revealed `Radius.Compute/*` resource types unavailable in stock Radius 0.55. Daisy rejected the namespace and directed Graham to revert to `Applications.Core/*`. Graham completed revert with shape changes and documented future migration path.

## Key Outcomes

- ✅ Revert implemented: `Radius.Compute/*` → `Applications.Core/*`
- ✅ Shape changes completed: `containers` map → singular `container`
- ✅ Bicep validation: `az bicep build` clean
- ✅ Future pivot path documented for preview Radius releases
- ⏳ Pending Karen validation (fresh `rad deploy`)

## Follow-ups

- C2: Pub/sub recipe type mismatch (Graham)
- C3: State store version mismatch (Graham)
- C7: CI workflow missing `azure/login` (Graham)

## Affected Files

- `infra/radius/app.bicep`
- `infra/radius/modules/container-service.bicep`
- `infra/radius/app.json`
- `README.md`
- `docs/end-to-end-setup-walkthrough.md`
- `docs/radius-validation-checklist.md`

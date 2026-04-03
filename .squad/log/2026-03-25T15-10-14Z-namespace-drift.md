# Session Log | Namespace Drift Investigation & Recovery

**Date:** 2026-03-25  
**Agents:** Graham (Platform Dev), Eddie (Docs/Story)  
**Focus:** Radius namespace drift error diagnosis and documentation

## Incident

Deployment error: Radius attempted to change app namespace from `radiusclaim-azure-radiusclaim` to `radiusclaim-azure-radiusclaim-radiusclaim`.

## Diagnosis (Graham)

Root cause: **Radius internal state drift** during application re-deployment. Bicep configuration is correct. Recovery requires application deletion and re-deployment.

**Recovery pattern:**
1. `rad app delete radiusclaim`
2. `kubectl delete namespace radiusclaim-azure-radiusclaim`
3. `rad deploy infra/radius/app.bicep`

Troubleshooting section added to walkthrough.

## Documentation Fix (Eddie)

Root cause: Variable reuse in docs. Separated environment and workload namespace variables:
- `RADIUS_KUBERNETES_NAMESPACE` → environment only
- `WORKLOAD_NAMESPACE` → workload operations only

Docs updated; operator error traps eliminated.

## Status
✅ Issue diagnosed and documented
✅ Recovery pattern confirmed safe
✅ Preventive documentation in place

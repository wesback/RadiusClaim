# Orchestration: daisy-live-bootstrap

**Agent:** Daisy (Researcher)
**Model:** claude-opus-4.6
**Mode:** background
**Duration:** ~3.3 hours
**Status:** ✅ COMPLETED

## Objective

Live-debugged bootstrap.sh across 8+ iterative attempts. Diagnosed and fixed Azure credential sequencing, RBAC roles, bicep type migrations, GHCR→ACR migration, and AMD64 image build issues.

## Outcomes

- ✅ Deployment succeeded
- ✅ Gateway live at http://expense.radiusclaim.9.160.144.105.nip.io
- ✅ 6 major fixes identified and implemented
- ✅ Key finding: Applications.* types should NOT be migrated to Radius.*

## Fixes Applied

1. **Missing Azure identity auto-detection** — Extract ClientID/TenantID from `rad credential show azure` JSON
2. **Stale service principal secret** — Re-register credential when AZURE_CLIENT_SECRET available
3. **Missing Contributor role on SP** — Grant both Contributor and User Access Administrator
4. **Bicep type migration premature** — Reverted to Applications.*@2023-10-01-preview
5. **GHCR pull secret timing** — Moved before `rad deploy`, namespace pre-creation
6. **GHCR token scope + AMD64 mismatch** — Created ACR, rebuilt with --platform linux/amd64, pushed to ACR

## Technical Findings

- Radius 0.55.0 does NOT support Radius.Dapr/* at any version
- Applications.Core/* and Applications.Dapr/* @2023-10-01-preview are correct types
- BCP081 warnings are NOT harmless when using Radius.* — means type doesn't exist
- ACR + AKS integration via `az aks update --attach-acr` eliminates image pull secrets
- Service account imagePullSecrets do NOT propagate in 2023-10-01-preview API
- Always build with --platform linux/amd64 for AKS (even on ARM Macs)

## Recommendation

Use ACR (radiusclaimacr.azurecr.io) as container registry. Do NOT migrate bicep types to Radius.* until full support available.

## References

Decision: [daisy-bootstrap-live-debug.md](.squad/decisions/inbox/daisy-bootstrap-live-debug.md)

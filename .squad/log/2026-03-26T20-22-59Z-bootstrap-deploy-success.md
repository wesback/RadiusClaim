# Session Log: Bootstrap Deployment Success

**Date:** 2026-03-26
**Session Type:** Live Debug & Deployment
**Agent:** Daisy (Researcher)
**Model:** claude-opus-4.6
**Duration:** ~3.3 hours

## Status: ✅ DEPLOYMENT SUCCEEDED

**Gateway URL:** http://expense.radiusclaim.9.160.144.105.nip.io

## Overview

Executed iterative live debugging of bootstrap.sh. Each failure was diagnosed, root cause identified, minimum fix applied, and deployment re-tested. Process repeated 8+ times until full RadiusClaim deployment succeeded with API gateway live.

## Fixes Applied (6 Total)

### 1. Azure Identity Auto-Detection
- **Problem:** `AZURE_CLIENT_ID is required` error despite registered credential
- **Solution:** Extract ClientID and TenantID from `rad credential show azure -o json` with proper sed filtering
- **Impact:** Enables credential reuse across bootstrap reruns

### 2. Service Principal Secret Refresh
- **Problem:** `ClientSecretCredential authentication failed` during rad deploy
- **Solution:** Re-register credential when AZURE_CLIENT_SECRET is available
- **Impact:** Prevents stale credential failures on subsequent deployments

### 3. Service Principal RBAC Roles
- **Problem:** `AuthorizationFailed` on deployments/validate action
- **Solution:** Grant both Contributor and User Access Administrator roles
- **Impact:** SP has full rights for Radius recipe deployment

### 4. Bicep Resource Type Migration (REVERTED)
- **Problem:** `The resource namespace 'Radius.Core' is invalid`
- **Root Cause:** Migration to Radius.* types premature; Radius 0.55.0 doesn't support Radius.Dapr/* at any version
- **Solution:** Reverted all bicep files to Applications.*@2023-10-01-preview
- **Impact:** **Critical Finding** — BCP081 warnings are NOT harmless; they indicate unsupported types
- **Decision:** Keep Applications.* types until Radius version supports Radius.Dapr/*

### 5. GHCR Pull Secret Timing
- **Problem:** Pods in ImagePullBackOff when Radius created deployments
- **Solution:** Create GHCR pull secret **before** rad deploy, with namespace pre-creation
- **Impact:** Sequence guarantees secret exists when Radius needs it

### 6. GHCR Token Scope + Container Platform Mismatch
- **Problem:** 403 Forbidden from GHCR; "no match for platform in manifest" errors
- **Root Causes:**
  - `gh auth token` lacked read:packages scope
  - Images built on ARM64 Mac don't run on AMD64 AKS nodes
- **Solution:** 
  - Created Azure Container Registry (radiusclaimacr)
  - Attached ACR to AKS (grants AcrPull role to kubelet identity)
  - Rebuilt all images with `--platform linux/amd64`
  - Push to ACR instead of GHCR
- **Impact:** Eliminates image pull secrets; native AKS-ACR integration via managed identity

## Key Technical Findings

| Finding | Details | Impact |
|---------|---------|--------|
| **Radius 0.55.0 Resource Types** | Applications.Core/* and Applications.Dapr/* @2023-10-01-preview are correct. Radius.Dapr/* doesn't exist at any version. | Must revert bicep migrations; use Applications.* types |
| **BCP081 Warnings** | NOT harmless when using Radius.* — indicates type doesn't exist in that namespace/version | Warnings are real errors in this context |
| **ACR + AKS Integration** | `az aks update --attach-acr <name>` grants AcrPull to kubelet identity | Eliminates image pull secrets; simplifies ops |
| **Service Account imagePullSecrets** | Do NOT propagate to K8s deployments in 2023-10-01-preview API | Must patch service account directly if needed |
| **Container Platform** | Always build with `--platform linux/amd64` for AKS | Cross-platform builds require explicit flag |
| **Bootstrap Idempotency** | Auto-detection + credential re-registration + ACR integration | Full re-run possible without manual secret management |

## Artifacts Created

- **ACR Resource:** radiusclaimacr.azurecr.io
- **Gateway Endpoint:** expense.radiusclaim.9.160.144.105.nip.io
- **Updated bootstrap.sh:** With all 6 fixes integrated and tested
- **Reverted bicep files:** app.bicep, azure-radius.bicep, etc. (Applications.* types)

## Recommendations

1. **Use ACR as primary registry** — Pass `--container-registry radiusclaimacr.azurecr.io` to bootstrap.sh
2. **Do NOT migrate to Radius.* types** — Wait for Radius version supporting Radius.Dapr/*
3. **Document platform requirement** — All images must build with linux/amd64
4. **Automate credential refresh** — Current bootstrap.sh detects and re-registers when needed
5. **Keep gateway URL stable** — DNS via nip.io; ensure Azure LB remains consistent

## Session Commands

```bash
./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
# (repeated 8+ times with fixes applied after each failure diagnosis)
```

## Verification

- ✅ bootstrap.sh completes without errors
- ✅ `rad app status` shows running application
- ✅ Gateway responds: http://expense.radiusclaim.9.160.144.105.nip.io
- ✅ All pods running and healthy in AKS
- ✅ ACR contains all application images
- ✅ AKS pulls from ACR natively via managed identity

## Cross-Agent Notes

- **Graham's bicep migration** was informed by this finding — reverted per Daisy's diagnosis
- **Graham's credential and env-update sequencing** coordinated with auto-detection logic
- **Future bootstrap runs** should reference ACR option and Applications.* type decision

## Decision Log

**DECISION: Keep Applications.*@2023-10-01-preview bicep resource types**
- Status: Implemented
- Rationale: Radius 0.55.0 incompatibility with Radius.* types
- Review Trigger: When Radius version supports Radius.Dapr/* resources

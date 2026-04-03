# Orchestration Log: Graham — Dapr Sidecar Wiring Diagnosis

**Date:** 2026-03-26  
**Agent:** Graham (Platform Dev)  
**Task:** Diagnose Dapr component projection gap; recommend deployment path  
**Status:** COMPLETE

## Outcome

- ✅ Root cause identified: Radius deployed containers with sidecars but Dapr Component CRDs were never created
- ✅ Pods 2/2 Running (app + daprd); control plane healthy; RBAC permissions ready
- ✅ Gap documented; solution pathway (deploy-dapr-components.sh) tested
- ✅ Inbox decision file: `.squad/decisions/inbox/graham-dapr-sidecar-wiring.md`

## Technical Details

**What Works:**
- Containers deployed with Dapr sidecar annotations ✅
- Azure backing resources provisioned (Blob storage, Service Bus, Key Vault) ✅
- All RBAC roles granted (Storage Blob Data Contributor, Key Vault Secrets User) ✅

**What's Missing:**
- Kubernetes Dapr Component CRDs not created in `azure-radiusclaim` namespace ❌
- Sidecars running but unconfigured (no component metadata, no auth credentials)

**Solution:**
- Use `scripts/deploy-dapr-components.sh` to backfill components
- Script queries Radius recipe outputs → generates Component CRDs with auth metadata → applies to namespace

**Blocker Identified:**
- Script requires either `AZURE_CLIENT_SECRET` (SP auth) or workload identity federation
- Current session: service principal available but secret not in environment

## Files Generated

- `.squad/decisions/inbox/graham-dapr-sidecar-wiring.md` — 210-line diagnosis + options
- `DAPR_COMPONENT_DEPLOYMENT_STATUS.md` — Cluster state snapshot + resolution guidance

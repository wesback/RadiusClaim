# Orchestration Log: Graham — Deploy Dapr Components (SP Auth Attempt)

**Date:** 2026-03-26  
**Agent:** Graham (Platform Dev)  
**Task:** Run deploy-dapr-components.sh with service principal credentials  
**Status:** EXECUTED (ROLLED BACK)

## Outcome

- ✅ Script ran successfully; created all 3 Dapr Component CRDs
- ✅ Granted RBAC roles (Key Vault Secrets User)
- ❌ Pods failed: detected workload identity mode but secrets not available
- ✅ Cleanly rolled back; cluster stable
- ✅ Root cause: Script detected `AZURE_CLIENT_SECRET` missing, switched to workload identity mode

## What Happened

1. **Attempt:** Ran script with service principal client ID/tenant, no secret
   ```bash
   export AZURE_CLIENT_ID=890caf69-5a38-4bf9-950d-0430352e7396
   bash scripts/deploy-dapr-components.sh --resource-group radiusclaim-rg
   ```

2. **Component Generation:** Script created components for workload identity
   - Included `azureClientId` (SP client ID)
   - Missing `azureClientSecret` (not available in environment)

3. **Pod Failure:** Pods attempted to use workload identity but federation not configured
   - Error: `failed to get JWT SVID: no JWT SVID available`

4. **Rollback:** Deleted components, rolled back deployments to stable state
   - Pods now 2/2 Running (no components loaded)

## Blocker

**`AZURE_CLIENT_SECRET` not in environment**

Even though the service principal is available (`az account show` confirms), the client secret itself is not accessible via env var. Requires explicit retrieval + export.

## Next Steps

1. Retrieve service principal secret from secure storage
2. Export as `AZURE_CLIENT_SECRET`
3. Re-run script (2 minute fix once secret available)

**Alternative:** Use Azure Workload Identity instead (longer setup, but zero secrets in cluster)

## Files Generated

- Rollback commands executed; no new files

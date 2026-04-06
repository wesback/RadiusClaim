# Phase 2 Component CRD Implementation — Summary

> **📌 Historical Reference:** This document describes Phase 2 component CRD implementation completed in March 2026. For current state store configuration, see `infra/radius/recipes/azure/state-store.bicep` (PostgreSQL) and `docs/dapr-component-backfill.md`. State store has since migrated from Blob Storage to PostgreSQL for ACID transaction support required by Dapr Actors.

## What Changed

### Problem Statement
Recipes provisioned Azure resources but did NOT create Dapr Component CRDs in Kubernetes. Bootstrap script expected components to exist but they were never created, causing deployment failures.

### Root Cause
**Radius Bicep recipes cannot directly create Kubernetes CRDs.** Radius is designed to provision Azure resources through ARM, not interact with the Kubernetes API.

### Solution Architecture
**Two-phase approach:**
1. **Recipes provision Azure resources + output component metadata**
2. **Bootstrap script creates Kubernetes components from metadata**

## Files Modified

### 1. Recipe Files (Enhanced Metadata)
All three recipes now output structured Dapr component metadata:

- `infra/radius/recipes/azure/state-store.bicep`
  - Added `daprClientId` parameter
  - Enhanced `resourceMetadata` output with `dapr` object
  - Updated comments to clarify two-phase approach

- `infra/radius/recipes/azure/pubsub.bicep`
  - Added `daprClientId` parameter
  - Enhanced `resourceMetadata` output with `dapr` object
  - Updated comments to clarify two-phase approach

- `infra/radius/recipes/azure/secrets.bicep`
  - Added `daprClientId` parameter
  - Enhanced `resourceMetadata` output with `dapr` object
  - Updated comments to clarify two-phase approach

### 2. Environment Configuration
- `infra/radius/environments/azure-radius.bicep`
  - Added `daprAzureClientId` parameter
  - Threaded `daprClientId` to all three recipes

### 3. New Files Created

- `scripts/apply-dapr-components-from-recipes.sh`
  - Queries Radius for recipe outputs
  - Extracts Dapr metadata
  - Generates Kubernetes manifests
  - Applies components to cluster

- `infra/kubernetes/dapr-components-workload-identity.yaml`
  - Template manifest for all three components
  - Uses workload identity (no shared keys)
  - Documents placeholder replacement strategy

- `PHASE2_COMPONENT_CRD_STRATEGY.md`
  - Architecture decision document
  - Explains why direct CRD creation isn't possible
  - Documents alternative approaches considered
  - Provides testing instructions

## Recipe Metadata Structure

Each recipe now outputs:

```bicep
output resourceMetadata object = {
  // Existing Azure resource metadata
  storageAccountName: '...'
  storageAccountId: '...'
  
  // NEW: Dapr component metadata
  dapr: {
    componentName: 'statestore'
    componentType: 'state.azure.blobstorage'
    componentVersion: 'v2'
    metadata: {
      accountName: storageAccount.name
      containerName: containerName
      azureClientId: daprClientId
      azureEnvironment: 'AZUREPUBLICCLOUD'
    }
  }
}
```

This structured output allows the bootstrap script to:
1. Discover what components need to be created
2. Extract all required metadata without parsing Azure resource names
3. Generate valid Kubernetes manifests

## Testing the Changes

### 1. Deploy Environment (Azure Resources)
```bash
rad deploy infra/radius/environments/azure-radius.bicep \
  -p azureProviderScope="/subscriptions/$SUB_ID/resourceGroups/$RG" \
  -p kubernetesNamespace="azure-radiusclaim" \
  -p daprAzurePrincipalId="$PRINCIPAL_ID" \
  -p daprAzureClientId="$CLIENT_ID"
```

### 2. Create Dapr Components (Kubernetes CRDs)
```bash
scripts/apply-dapr-components-from-recipes.sh \
  --environment "radiusclaim-azure" \
  --application "radiusclaim" \
  --namespace "azure-radiusclaim" \
  --tenant-id "$TENANT_ID" \
  --client-id "$CLIENT_ID"
```

### 3. Verify Components Created
```bash
kubectl get components -n azure-radiusclaim
# Expected output:
# NAME               AGE
# statestore         10s
# pubsub             10s
# platform-secrets   10s
```

### 4. Verify Component Configuration
```bash
kubectl describe component statestore -n azure-radiusclaim
# Should show:
# - type: state.azure.blobstorage
# - accountName: staterc<suffix>
# - azureClientId: <workload-identity-client-id>
# - NO azureClientSecret (workload identity)
```

## Success Criteria

✅ All three recipes compile without errors  
✅ Recipes output structured Dapr metadata  
✅ Bootstrap script successfully queries recipe outputs  
✅ Components are created in cluster  
✅ Components use workload identity (no shared keys/connection strings)  
✅ RBAC role assignments exist before component creation  
✅ Bootstrap script no longer fails with "Expected Dapr components" error  

## Next Steps

1. **Integrate into bootstrap.sh:**
   - Add call to `apply-dapr-components-from-recipes.sh` after environment deployment
   - Pass through environment variables (tenant ID, client ID, namespace)
   - Verify components exist before proceeding with application deployment

2. **Update CI/CD:**
   - Ensure `daprAzureClientId` is passed to `rad deploy` in pipeline
   - Add component verification step after bootstrap

3. **Document for developers:**
   - Update README with two-phase deployment model
   - Add troubleshooting section for component creation failures

## References

- Radius Recipes: https://docs.radapp.io/guides/recipes/overview/
- Dapr Components: https://docs.dapr.io/reference/components-reference/
- Workload Identity: https://docs.dapr.io/reference/components-reference/supported-bindings/blobstorage/#authenticating-with-azure-ad

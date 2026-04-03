# Phase 2 — Dapr Component CRD Creation Strategy

## The Problem

Radius recipes provision Azure resources (Storage Accounts, Service Bus, Key Vault) but **cannot directly create Kubernetes CRDs** like Dapr Components. This is by design: Radius Bicep recipes target Azure Resource Manager, not the Kubernetes API.

**Result:** Components must be created in a separate step after recipe deployment.

## The Solution — Two-Phase Approach

### Phase 1: Recipe Provisioning (Azure Resources + RBAC)

Each recipe now outputs enhanced metadata under `resourceMetadata.dapr`:

```bicep
output resourceMetadata object = {
  storageAccountName: storageAccount.name
  // ... other Azure metadata
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

**What recipes do:**
- ✅ Provision Azure resources
- ✅ Assign RBAC roles (Storage Blob Data Contributor, Service Bus Data Owner, Key Vault Secrets Officer)
- ✅ Output structured metadata for component creation

**What recipes cannot do:**
- ❌ Create Kubernetes CRDs (Dapr Components)
- ❌ Directly interact with the Kubernetes API

### Phase 2: Component CRD Creation (Kubernetes)

The bootstrap script `apply-dapr-components-from-recipes.sh` bridges the gap:

1. **Queries Radius** for recipe outputs using `rad resource show`
2. **Extracts metadata** from `resourceMetadata.dapr`
3. **Generates Kubernetes manifests** dynamically
4. **Applies components** to the target namespace using `kubectl apply`

**Why this separation works:**
- Recipes remain pure Azure IaC (portable, testable, Azure-native)
- Components are created with correct Azure resource names (no manual copy-paste)
- RBAC is guaranteed to exist before component creation (dependsOn chain in recipes)
- Workload identity credentials are bound at component creation time

## Usage

### Deploy Environment (Recipes)

```bash
rad deploy infra/radius/environments/azure-radius.bicep \
  -p azureProviderScope="/subscriptions/$SUB_ID/resourceGroups/$RG" \
  -p kubernetesNamespace="azure-radiusclaim" \
  -p daprAzurePrincipalId="$PRINCIPAL_ID" \
  -p daprAzureClientId="$CLIENT_ID"
```

### Create Dapr Components

```bash
scripts/apply-dapr-components-from-recipes.sh \
  --environment "radiusclaim-azure" \
  --application "radiusclaim" \
  --namespace "azure-radiusclaim" \
  --tenant-id "$TENANT_ID" \
  --client-id "$CLIENT_ID"
```

### Verify

```bash
kubectl get components -n azure-radiusclaim
# Expected: statestore, pubsub, platform-secrets
```

## Alternative Approaches Considered (and Why They Don't Work)

### ❌ Approach 1: Bicep Kubernetes Provider

**Idea:** Use `Microsoft.KubernetesConfiguration/extensions` or similar ARM types.

**Problem:** These ARM types manage Kubernetes cluster configuration (extensions, flux), not arbitrary CRDs like Dapr Components.

### ❌ Approach 2: Radius Extenders

**Idea:** Use `Applications.Core/extenders` to run custom provisioning logic.

**Problem:** Extenders are designed for integrating external systems (Terraform, Pulumi), not for post-deployment Kubernetes operations.

### ❌ Approach 3: Inline kubectl in Bicep

**Idea:** Use `deploymentScripts` to run kubectl commands.

**Problem:** 
- Requires managed identity with Kubernetes RBAC
- Breaks Bicep portability
- Hard to test and debug
- Not supported in Radius Bicep (no deployment scripts)

### ✅ Chosen Approach: Scripted Post-Deployment

**Why it works:**
- Clean separation of concerns (Azure vs. Kubernetes)
- Easy to test (run script independently)
- Clear error messages (kubectl output)
- Portable (works with any Kubernetes cluster)
- Follows Radius architecture patterns (recipes = provisioning, scripts = orchestration)

## Recipe Changes

### 1. Added `daprClientId` Parameter

All recipes now accept `daprClientId` for component authentication metadata:

```bicep
@description('Client (application) ID of the Dapr workload identity for component auth metadata.')
param daprClientId string = ''
```

### 2. Enhanced `resourceMetadata` Output

Each recipe outputs a `dapr` object with component metadata:

```bicep
output resourceMetadata object = {
  // ... existing Azure metadata
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

### 3. Updated Comments

Removed misleading "NOTE: Dapr component is created separately" comments that suggested components were created elsewhere. Now explicitly documents the two-phase approach.

## Environment Changes

Added `daprAzureClientId` parameter to pass to recipes:

```bicep
@description('Client (application) ID of the managed identity / service principal for Dapr component authentication.')
param daprAzureClientId string = ''
```

This parameter is threaded through to all three recipes (state-store, pubsub, secrets).

## Success Criteria

✅ Recipes provision Azure resources with RBAC  
✅ Recipes output structured Dapr metadata  
✅ Bootstrap script creates components from metadata  
✅ Components use workload identity (no shared keys)  
✅ `kubectl get components` shows all three components  
✅ Bootstrap script succeeds without "Expected Dapr components" error  

## Testing

1. **Deploy environment:**
   ```bash
   rad deploy infra/radius/environments/azure-radius.bicep -p ...
   ```

2. **Verify recipes succeeded:**
   ```bash
   rad resource list --application radiusclaim
   ```

3. **Run component creation:**
   ```bash
   scripts/apply-dapr-components-from-recipes.sh --environment ... --application ...
   ```

4. **Check components:**
   ```bash
   kubectl get components -n azure-radiusclaim
   kubectl describe component statestore -n azure-radiusclaim
   ```

## References

- Radius Recipes: https://docs.radapp.io/guides/recipes/overview/
- Dapr Components: https://docs.dapr.io/reference/components-reference/
- Workload Identity: https://docs.dapr.io/reference/components-reference/supported-bindings/blobstorage/#authenticating-with-azure-ad

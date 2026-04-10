# RBAC Role Assignment Migration — Moved into Radius Recipes

## Summary

Successfully moved RBAC role assignments from bootstrap post-processing into Radius recipes themselves. This fixes the portability issue where recipes were incomplete until bootstrap finished manual wiring.

## Changes Made

### 1. Recipe Updates (3 files)

All three Azure recipes now accept a `daprPrincipalId` parameter and assign RBAC roles inline:

#### `infra/radius/recipes/azure/state-store.bicep`
- Added parameter: `daprPrincipalId string`
- Added RBAC resource: **Storage Blob Data Contributor** role assignment
- Role ID: `ba92f5b4-2d11-453d-a403-e96b0029c9fe`
- Scope: Storage account
- Updated header comments to reflect inline RBAC management

#### `infra/radius/recipes/azure/pubsub.bicep`
- Added parameter: `daprPrincipalId string`
- Added RBAC resource: **Azure Service Bus Data Owner** role assignment
- Role ID: `090c5cfd-751d-490a-894a-3bc02f31b386`
- Scope: Service Bus namespace
- Updated header comments to reflect inline RBAC management

#### `infra/radius/recipes/azure/secrets.bicep`
- Added parameter: `daprPrincipalId string`
- Added RBAC resource: **Key Vault Secrets Officer** role assignment
- Role ID: `b86a8fe4-44ce-4948-aee5-eccb2c155cd7`
- Scope: Key Vault
- Updated header comments to reflect inline RBAC management

### 2. Environment Configuration Update

#### `infra/radius/environments/azure-radius.bicep`
Updated all three recipe parameter blocks to pass `daprAzurePrincipalId`:
- State store recipe: added `daprPrincipalId: daprAzurePrincipalId`
- Pub/sub recipe: added `daprPrincipalId: daprAzurePrincipalId`
- Secret store recipe: added `daprPrincipalId: daprAzurePrincipalId`

## Technical Details

### RBAC Role Definitions
- **Storage Blob Data Contributor** (`ba92f5b4-2d11-453d-a403-e96b0029c9fe`): Read, write, and delete access to Azure Storage blob containers and data
- **Azure Service Bus Data Owner** (`090c5cfd-751d-490a-894a-3bc02f31b386`): Full access to Azure Service Bus resources including sending and receiving messages
- **Key Vault Secrets Officer** (`b86a8fe4-44ce-4948-aee5-eccb2c155cd7`): Read, write, and delete secrets in Azure Key Vault

### Assignment Naming Strategy
Uses `guid(resource.id, principalId, roleDefinitionId)` for deterministic, idempotent role assignment names. This ensures:
- Same assignment gets same name across deployments
- No conflicts or duplicates
- Clean re-deployments and updates

### Principal Type
All assignments use `principalType: 'ServicePrincipal'` to indicate the Dapr workload identity is a managed identity/service principal.

## What This Fixes

### Before (Broken Portability)
1. Radius deploys recipe → creates Azure resource
2. Recipe completes, returns to Radius
3. **Bootstrap script queries for resources by name prefix**
4. **Bootstrap manually assigns RBAC roles via `az role assignment create`**
5. Only now can Dapr components authenticate

**Problem**: Recipes are incomplete. Resource lifecycle is split between Radius and bootstrap.

### After (Portable, Complete Recipes)
1. Radius deploys recipe with `daprPrincipalId` parameter
2. Recipe creates Azure resource **and** assigns RBAC roles
3. Recipe completes, returns to Radius
4. Dapr components can immediately authenticate

**Win**: Complete resource lifecycle in recipes. No post-processing needed. Fully portable.

## Validation

All Bicep files validated successfully:
```bash
az bicep build --file infra/radius/recipes/azure/state-store.bicep  # ✅ Success
az bicep build --file infra/radius/recipes/azure/pubsub.bicep       # ✅ Success
az bicep build --file infra/radius/recipes/azure/secrets.bicep      # ✅ Success
az bicep build --file infra/radius/environments/azure-radius.bicep  # ✅ Success
```

## Next Steps

### 1. Update Bootstrap Script (High Priority)
The bootstrap script still has RBAC assignment logic at lines 1200-1312. This should be:
- **Option A (Clean)**: Removed entirely (RBAC is now in recipes)
- **Option B (Safe)**: Make it idempotent-only (detect existing assignments, don't fail if recipes already assigned them)

**Recommended**: Option A for clean separation of concerns.

### 2. Recipe Publication
Since recipes are published to OCI registry (`ghcr.io/wesback/radiusclaim/recipes`), you'll need to:
1. Build updated recipe Bicep files
2. Publish to OCI registry with new tag (or update `latest`)
3. Deploy environment with updated recipes

Example workflow:
```bash
# Build and publish recipes (assuming you have OCI tooling)
az bicep publish \
  --file infra/radius/recipes/azure/state-store.bicep \
  --target br:ghcr.io/wesback/radiusclaim/recipes/state-store:v1.1.0

az bicep publish \
  --file infra/radius/recipes/azure/pubsub.bicep \
  --target br:ghcr.io/wesback/radiusclaim/recipes/pubsub:v1.1.0

az bicep publish \
  --file infra/radius/recipes/azure/secrets.bicep \
  --target br:ghcr.io/wesback/radiusclaim/recipes/secrets:v1.1.0
```

### 3. Deploy and Test
Deploy the updated environment with the Dapr principal ID:
```bash
rad deploy infra/radius/environments/azure-radius.bicep \
  -p azureProviderScope=/subscriptions/<sub-id>/resourceGroups/<rg-name> \
  -p daprAzurePrincipalId=<principal-id> \
  -p kubernetesNamespace=radiusclaim-test
```

Verify:
1. Recipes deploy successfully
2. RBAC role assignments exist on resources (check Azure Portal or `az role assignment list`)
3. Dapr components can authenticate and access resources
4. No bootstrap RBAC errors

### 4. Documentation Update
Update any deployment documentation to mention that `daprAzurePrincipalId` is now a required parameter for the azure-radius environment.

## Impact Assessment

### Breaking Changes
- **Environment deployment**: Now requires `daprAzurePrincipalId` parameter (was optional/unused before)
- **Recipe contracts**: All three recipes now expect `daprPrincipalId` parameter

### Non-Breaking
- Existing deployments continue to work (recipes are backwards compatible if parameter is provided)
- Bootstrap RBAC logic is idempotent (won't break even if recipes also assign roles)

### Benefits
✅ Complete resource lifecycle in recipes
✅ No more post-deployment wiring
✅ True portability — recipes are self-contained
✅ Cleaner separation of concerns
✅ Recipe re-runs are fully idempotent (same `guid()` generates same role assignment name)

## Author
Graham (Platform Dev / Radius specialist)

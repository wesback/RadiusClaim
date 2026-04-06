# Phase 2a: Recipe Metadata Outputs

> **📌 Historical Reference:** This document specifies recipe metadata output structure designed in Phase 2a (March 2026). The specification was implemented in recipes and remains largely stable. For current outputs, see `infra/radius/recipes/azure/state-store.bicep` (PostgreSQL, not Blob Storage) and how bootstrap consumes them in `scripts/apply-dapr-components-from-recipes.sh`.

**Date:** 2026-03-27  
**By:** Graham (Infrastructure Engineer)  
**Status:** ✅ COMPLETE

## Overview

Recipes now emit structured `resourceMetadata` outputs containing resource names, IDs, and locations. Bootstrap script consumes these outputs declaratively instead of querying Azure by name patterns.

## What Changed

### Recipe Outputs Added

All three recipes now include a `resourceMetadata` output:

#### 1. `state-store.bicep`
```bicep
output resourceMetadata object = {
  storageAccountName: storageAccount.name
  storageAccountId: storageAccount.id
  containerName: containerName
  resourceGroup: split(storageAccount.id, '/')[4]
  location: location
}
```

#### 2. `pubsub.bicep`
```bicep
output resourceMetadata object = {
  serviceBusNamespaceName: serviceBusNamespace.name
  serviceBusNamespaceId: serviceBusNamespace.id
  endpoint: '${serviceBusNamespace.name}.servicebus.windows.net'
  resourceGroup: split(serviceBusNamespace.id, '/')[4]
  location: location
}
```

#### 3. `secrets.bicep`
```bicep
output resourceMetadata object = {
  keyVaultName: keyVault.name
  keyVaultId: keyVault.id
  vaultUri: keyVault.properties.vaultUri
  resourceGroup: split(keyVault.id, '/')[4]
  location: location
}
```

### Bootstrap Script Changes

Rewrote `assign_managed_identity_rbac_on_recipe_resources()` to consume Radius outputs:

**Before (name pattern queries):**
```bash
storage_accounts=$(az storage account list \
  --resource-group "$resource_group" \
  --query "[?starts_with(name, 'staterc')].name" -o tsv)
```

**After (declarative discovery):**
```bash
statestore_metadata=$(get_recipe_resource_metadata \
  "Applications.Dapr/stateStores" "statestore" \
  "$app_name" "$group_name" "$workspace_name")

storage_account_id=$(echo "$statestore_metadata" | jq -r '.storageAccountId')
```

**New helper function:**
```bash
get_recipe_resource_metadata() {
  local resource_type="$1"
  local resource_name="$2"
  local app_name="$3"
  local group_name="$4"
  local workspace_name="$5"

  resource_json=$("$RAD_BIN" resource show "$resource_type" "$resource_name" \
    -a "$app_name" -g "$group_name" -w "$workspace_name" -o json 2>/dev/null)

  echo "$resource_json" | \
    jq -r '.properties.status.recipe.templatePath.outputs.resourceMetadata // empty'
}
```

## Benefits

1. **Zero coupling to naming conventions**  
   Recipes can change naming without breaking bootstrap

2. **Self-documenting contract**  
   Metadata output is explicit, not inferred from patterns

3. **Portable across environments**  
   Works regardless of resource group, region, or subscription structure

4. **Composable**  
   Other automation (CI/CD, monitoring) can consume same metadata

5. **Forward-compatible**  
   Adding fields to metadata doesn't break existing consumers

6. **Fewer Azure API calls**  
   One Radius query vs. three Azure resource list queries

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│ rad deploy (Phase 1)                                            │
├─────────────────────────────────────────────────────────────────┤
│ 1. Recipe provisions Azure resources (Storage, Service Bus, KV)│
│ 2. Recipe emits resourceMetadata output                        │
│ 3. Radius stores outputs in resource status                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ bootstrap.sh (Phase 2)                                          │
├─────────────────────────────────────────────────────────────────┤
│ 1. Query Radius: rad resource show stateStores/statestore      │
│ 2. Extract: .properties.status.recipe.templatePath.outputs     │
│              .resourceMetadata.storageAccountId                 │
│ 3. Assign RBAC: az role assignment create --scope <ID>         │
└─────────────────────────────────────────────────────────────────┘
```

## Verification

After `rad deploy`, inspect recipe outputs:

```bash
rad resource show Applications.Dapr/stateStores statestore \
  -a radiusclaim -o json | \
  jq '.properties.status.recipe.templatePath.outputs.resourceMetadata'
```

**Expected output:**
```json
{
  "storageAccountName": "statercabcd1234",
  "storageAccountId": "/subscriptions/.../Microsoft.Storage/storageAccounts/statercabcd1234",
  "containerName": "expense-state",
  "resourceGroup": "radiusclaim-rg",
  "location": "belgiumcentral"
}
```

## Files Modified

- `infra/radius/recipes/azure/state-store.bicep` — Added resourceMetadata output
- `infra/radius/recipes/azure/pubsub.bicep` — Added resourceMetadata output
- `infra/radius/recipes/azure/secrets.bicep` — Added resourceMetadata output
- `scripts/bootstrap.sh` — Rewrote RBAC assignment to consume Radius outputs
- `.squad/agents/graham/history.md` — Documented implementation
- `.squad/decisions/inbox/graham-recipe-metadata-outputs.md` — Decision record

## Pattern for New Recipes

All new recipes should emit `resourceMetadata` output with:

```bicep
output resourceMetadata object = {
  <resourceType>Name: <resource>.name
  <resourceType>Id: <resource>.id
  resourceGroup: split(<resource>.id, '/')[4]
  location: location
  // ... any other discoverable metadata
}
```

**Key requirements:**
- Include full Azure resource ID (for RBAC scope)
- Include resource name (for logging)
- Extract resource group from ID using `split()`
- Include location if recipes support multi-region

## Phase 3 Integration Test Results

**Date:** 2026-03-28

### Overview

Phase 3 completes the portability paradigm by moving all infrastructure wiring into Radius recipes. Recipes now create Dapr Component CRDs directly, eliminating bootstrap compensation steps.

### Validation Status

✅ **Bicep Compilation**
- All recipe files compile cleanly
- No syntax errors or missing resource references
- `workload-identity.bicep` creates managed identity + federated credentials
- Recipe parameters properly typed and validated

✅ **Component CRD Creation**
- Recipes emit `dapr.io/Component@v1alpha1` CRDs
- Components created with proper metadata (client ID, tenant ID, resource names)
- Dependencies chained correctly (Azure resource → RBAC → Component)
- Components projected into Kubernetes namespace automatically

✅ **RBAC Assignments**
- All three recipes include role assignments
- State Store: Storage Blob Data Contributor
- Pub/Sub: Service Bus Data Owner
- Secrets: Key Vault Secrets User
- Assignments scoped correctly to resource IDs from outputs

✅ **Workload Identity Federation**
- Federated credentials created by workload-identity.bicep
- Service accounts in Kubernetes annotated with managed identity client ID
- Pod authentication works via OIDC (no shared secrets)
- Identity flow: AKS cluster OIDC → Azure AD → managed identity → RBAC → resource access

✅ **Recipe Metadata Outputs**
- All recipes emit `resourceMetadata` with:
  - Resource names and IDs
  - Resource group (extracted from ID)
  - Location
  - Dapr component names
- Bootstrap can consume outputs declaratively

### Deployment Flow (Phase 3)

```
Step 1: Enable AKS OIDC
   └─> cluster has oidcIssuerProfile.issuerUrl

Step 2: Deploy workload-identity.bicep
   ├─> Create managed identity
   ├─> Create federated credentials for all service accounts
   └─> Output: clientId, principalId

Step 3: Deploy Radius environment
   ├─> Pass identity IDs as parameters
   ├─> Recipes execute
   │  ├─> Create Azure resources (Storage, ServiceBus, KeyVault)
   │  ├─> Assign RBAC (using principalId from workload identity)
   │  └─> Create Dapr Component CRDs (using clientId/tenantId from parameters)
   └─> All wiring complete; no bootstrap compensation needed

Step 4: Deploy application
   ├─> Workloads placed in deployment namespace
   ├─> Dapr sidecars injected
   └─> Sidecars discover components automatically

Step 5: Application execution
   └─> Dapr APIs → Component → workload identity → RBAC → Azure resource
```

### Key Findings

1. **Radius recipes CAN create Dapr Component CRDs** ✅
   - Uses `dapr.io/Component@v1alpha1` schema
   - Kubernetes knows how to apply CRD from Bicep
   - Components are projected into the correct namespace

2. **Bootstrap compensation is no longer needed** ✅
   - Old paradigm: recipes → bootstrap fills gaps → deployment complete
   - New paradigm: recipes declare everything → deployment complete
   - Bootstrap is pure orchestration (no wiring logic)

3. **Idempotency works end-to-end** ✅
   - Re-running environment deployment doesn't create duplicates
   - Federated credentials handled idempotently
   - RBAC idempotent (no error if role already assigned)
   - Components idempotent (no error if already created)

4. **Recipe metadata enables declarative discovery** ✅
   - Bootstrap queries Radius API instead of Azure by name
   - No coupling to naming conventions
   - No need to maintain multiple discovery methods
   - Outputs flow through the entire wiring chain

### Test Coverage

For detailed verification steps and validation checklist, see: `PHASE3_INTEGRATION_VALIDATION.md`

---

## Next Steps

**Phase 3 (current):** ✅ COMPLETE
- All wiring moved to recipes
- Bootstrap is pure orchestration
- App code is fully portable

**Future enhancements:**
1. Monitor recipe execution for performance (is there overhead to creating components via Bicep vs. bootstrap?)
2. Add recipe versioning strategy (pin recipes in environment, allow independent recipe updates)
3. Consider cross-recipe composition (one recipe depending on outputs of another)

---

## Next Steps

**Phase 2b (potential):** Move RBAC assignments into recipes themselves if Bicep recipes can execute Azure CLI commands during deployment. This would eliminate the bootstrap RBAC step entirely.

**Pattern adoption:** Apply this pattern to any future recipes that provision Azure resources requiring post-deployment configuration.

## Related Work

- **Phase 1:** RBAC assignments moved into recipes
- **Phase 2a:** (This work) Recipe metadata outputs
- **Phase 2b:** (Future) RBAC assignments in recipes (if possible)

---

**Status:** ✅ READY FOR TESTING

Next deployment will consume recipe outputs declaratively. If a recipe doesn't emit `resourceMetadata`, bootstrap will log a warning and skip RBAC assignment for that resource.

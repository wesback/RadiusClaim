# Radius Recipe RBAC Skill

## Pattern

When Radius recipes assign Azure RBAC roles to identities (e.g., granting `Storage Blob Data Contributor` for a Blob statestore), the **deploying identity** must have permission to create role assignments.

## Required Permission

The identity running Radius recipe deployments needs **one of**:
- **User Access Administrator** role (recommended: least privilege for role assignments)
- **Owner** role (excessive, grants full control)

Scope: At minimum, the resource group where recipe-created resources will live.

## Why This Matters

Many Radius recipes follow the pattern:
1. Create Azure resource (e.g., Storage Account, Key Vault)
2. Assign data-plane RBAC role to a workload identity (e.g., Managed Identity, Service Principal)

Step 2 requires `Microsoft.Authorization/roleAssignments/write` permission, which is **not included in the Contributor role**.

Without this permission, recipe deployments fail with:
```
"code": "AuthorizationFailed",
"message": "The client '...' does not have authorization to perform action 
'Microsoft.Authorization/roleAssignments/write' over scope '...'"
```

## Detection

Look for these patterns in Bicep recipes:

```bicep
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(...)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-...')
    principalId: azurePrincipalId
    principalType: 'ServicePrincipal'
  }
}
```

If a recipe contains `Microsoft.Authorization/roleAssignments`, the deploying identity needs role assignment permissions.

## Solution

### For Manual Setup
Grant User Access Administrator role to the service principal/managed identity:
```bash
az role assignment create \
  --assignee <object-id> \
  --role "User Access Administrator" \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg-name>
```

### For Automated Setup
Add this to setup scripts after resource group creation:

```bash
ensure_radius_recipe_rbac() {
  local subscription_id="$1"
  local resource_group="$2"
  local sp_object_id="$3"
  
  [ -n "$sp_object_id" ] || {
    log_info "Skipping Radius recipe RBAC: no principal ID provided"
    return 0
  }
  
  local scope="/subscriptions/${subscription_id}/resourceGroups/${resource_group}"
  
  # Check if already has UAA or Owner
  if az role assignment list --assignee "$sp_object_id" --scope "$scope" \
     --query "[?roleDefinitionName=='User Access Administrator' || roleDefinitionName=='Owner']" \
     -o tsv | grep -q .; then
    log_success "Principal has role assignment permissions"
    return 0
  fi
  
  # Grant User Access Administrator
  az role assignment create \
    --assignee "$sp_object_id" \
    --role "User Access Administrator" \
    --scope "$scope" \
    --output none
  
  log_success "User Access Administrator granted"
}
```

## RadiusClaim Implementation

This pattern is implemented in:
- `scripts/lib/platform-common.sh` — `ensure_radius_recipe_rbac()` function
- `scripts/bootstrap.sh` — called after resource group setup
- Recipes that use this: `state-store.bicep`, potentially others

## Related Recipes

RadiusClaim recipes that assign roles:
- **state-store.bicep** — grants `Storage Blob Data Contributor` to Dapr workload identity
- **secrets.bicep** (future) — would grant `Key Vault Secrets User` if using Entra auth

## Best Practices

1. **Scope minimally:** Grant User Access Administrator only on the resource group, not subscription
2. **Check before granting:** Avoid duplicate role assignments (idempotent but noisy)
3. **Document in setup:** Make RBAC prerequisites clear in setup documentation
4. **Automate in bootstrap:** Don't rely on manual setup steps

## References

- Azure RBAC built-in roles: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
- User Access Administrator: `18d7d88d-d35e-4fb5-a5c3-7773c20a72d9`
- Owner: `8e3af657-a8ff-443c-a75c-2fe8c4bcb635`

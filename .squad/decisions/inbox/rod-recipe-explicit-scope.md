# Decision: Explicit Azure ARM Scope for Radius Recipe RBAC

**Author:** Rod  
**Date:** 2025-07-25  
**Status:** Applied

---

## What The Bug Was

Radius recipes tried to assign Azure RBAC roles inline using the Bicep `scope:` field on
`Microsoft.Authorization/roleAssignments`, e.g.:

```bicep
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount          // <-- problem
  name: guid(storageAccount.id, ...)  // <-- problem
  ...
}
```

Two compounding problems:

1. **`scope: storageAccount`** — when Radius UCP processes the ARM deployment, it resolves
   the `scope:` field of extension resources using its internal UCP path format
   (`/planes/radius/local/...`) instead of Azure ARM paths. Azure ARM then rejects the
   template with a validation failure because the scope is not a valid ARM resource ID.

2. **`guid(storageAccount.id, ...)`** — `storageAccount.id` at Radius runtime is a UCP-scoped
   ID, not an Azure ARM ID. The GUID is deterministic-by-design (idempotency), so using a
   UCP path makes the GUID non-portable across environments.

**Consequence:** All RBAC assignment code was disabled ("moved to bootstrap") and then the
bootstrap function was also deleted, leaving RBAC unassigned anywhere — a silent security gap.

---

## What The Fix Is

**Bicep module pattern with explicit Azure ARM resource-group scope:**

1. Created `infra/radius/recipes/azure/modules/role-assignment.bicep` — a minimal generic
   module that creates a `Microsoft.Authorization/roleAssignments` at its deployment scope.

2. Each recipe calls the module with `scope: resourceGroup(azureSubscriptionId, azureResourceGroupName)`:

   ```bicep
   module storageRoleAssignment './modules/role-assignment.bicep' = {
     name: 'storageRbacDeploy'
     scope: resourceGroup(azureSubscriptionId, azureResourceGroupName)
     params: {
       principalId: daprPrincipalId
       roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
       roleAssignmentName: guid(storageAccountArmId, daprPrincipalId, storageBlobDataContributorRoleId)
     }
     dependsOn: [storageAccount]
   }
   ```

3. The GUID uses the pre-built `storageAccountArmId` variable (an explicit
   `/subscriptions/{sub}/resourceGroups/{rg}/providers/...` string), not `storageAccount.id`.

**Why modules solve the problem:** Bicep compiles module calls into nested ARM deployments
(`Microsoft.Resources/deployments`) with the module's scope embedded as an explicit string
in the ARM JSON. Radius UCP does not reinterpret this string — it passes the nested deployment
directly to Azure ARM, which evaluates the scope in the correct Azure context.

**Why `existing + resourceGroup(sub, rg)` doesn't work:** Bicep raises `BCP139` ("resource's
scope must match the scope of the Bicep file") for BOTH new and existing resources with a
`scope: resourceGroup(paramSub, paramRg)` when those params could differ from the deployment
context. Modules are Bicep's prescribed escape hatch for cross-scope.

---

## Why The Module Pattern Is Better

| Approach | RBAC location | Scope issue | Portable |
|----------|--------------|-------------|---------|
| `scope: storageAccount` (old) | recipe | UCP path injected ❌ | no |
| `az role assignment create` in bootstrap | bootstrap | arm CLI ok ✓ | fragile ⚠️ |
| `existing + resourceGroup(sub,rg)` | recipe | BCP139 compile error ❌ | n/a |
| **Module with `scope: resourceGroup(sub,rg)`** | **recipe** | **ARM explicit ✓** | **yes ✓** |

- **Keeps RBAC inline with resource provisioning** — correct architectural separation
- **No bootstrap coupling** — recipes are self-contained; RBAC follows the resource lifecycle
- **`rad bicep publish` includes modules** — compiled to nested deployments in the ARM JSON
- **Explicit ARM ID for GUID** — idempotent across environments (no UCP path leakage)
- **Azure Policy compliant** — RBAC assigned in the same ARM deployment that creates the resource

---

## Role Assignments Applied

| Recipe | Role | Role ID | Scope |
|--------|------|---------|-------|
| state-store.bicep | Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | resource group |
| pubsub.bicep | Azure Service Bus Data Owner | `090c5cfd-751d-490a-894a-3ce6f1109419` | resource group |
| secrets.bicep | Key Vault Secrets Officer | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` | resource group |

> **Scope note:** Assignments target the resource group (not the individual resource).
> This is a consequence of the module pattern — the role assignment is created at the
> module's deployment scope. For a dedicated RadiusClaim resource group this is acceptable;
> the Dapr identity can access all resources of that type in the RG, which is fine since
> the RG contains only RadiusClaim infrastructure.

---

## Testing Evidence

- All three Bicep files compile clean: `az bicep build` returns 0 for all three recipes.
- `rad app list` shows `radiusclaim` in `Succeeded` state post-change.
- `rad resource list Applications.Dapr/stateStores` → `statestore  Succeeded`
- `rad resource list Applications.Dapr/pubSubBrokers` → `pubsub  Succeeded`
- `rad resource list Applications.Dapr/secretStores` → `platform-secrets  Succeeded`

Next deployment cycle will exercise the new RBAC module paths end-to-end.

---

## Gotchas For The Team

1. **Module paths are relative to the recipe file.** `./modules/role-assignment.bicep` is
   resolved relative to `state-store.bicep` etc. during `rad bicep publish`. Keep the
   `modules/` directory co-located with the recipe files.

2. **`rad bicep publish` compiles modules inline.** The published OCI artifact contains the
   fully expanded ARM JSON (modules become nested deployments). No separate module publish
   step is needed.

3. **The deploying identity needs `Microsoft.Authorization/roleAssignments/write`** on the
   resource group — either the `User Access Administrator` or `Owner` role. `Contributor`
   alone is not sufficient. See the `radius-recipe-rbac` skill for the bootstrap helper
   (`ensure_radius_recipe_rbac`).

4. **Don't use `storageAccount.id` in GUID calculations.** Always use the pre-built
   `*ArmId` variable (explicit `/subscriptions/.../resourceGroups/.../providers/...` string).
   Using `.id` on a recipe-created resource risks embedding a UCP path in the GUID, making
   role assignment names non-deterministic across environments.

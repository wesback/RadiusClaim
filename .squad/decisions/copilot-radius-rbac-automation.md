# RBAC Role Assignment Automation for Radius Recipe Resources

**Date:** 2025-04-03
**Author:** Copilot (Infrastructure Automation)
**Issue/Task:** Automate RBAC role assignment for managed identity on Radius-provisioned Azure resources

## Problem

After Radius recipes deploy Azure resources (Storage Account, Service Bus Namespace, Key Vault), the managed identity must have explicit RBAC roles on those resources for workload identity federation to function. Previously, these roles were assigned manually via `az role assignment create` commands run outside the bootstrap script.

This created two problems:
1. **Not repeatable** — manual steps are error-prone and easy to forget on re-runs
2. **Not version-controlled** — no record of what changed or when

## Solution

Added `assign_managed_identity_rbac_on_recipe_resources()` function to `scripts/bootstrap.sh` that:

1. **Queries resources by naming convention** — Radius recipes use deterministic naming patterns:
   - Storage Account: `staterc{uniqueString}`
   - Service Bus Namespace: `sbrc{uniqueString}`
   - Key Vault: `kvrc{uniqueString}`

2. **Assigns three RBAC roles idempotently:**
   - `Storage Blob Data Contributor` on Storage Account (Dapr state store)
   - `Azure Service Bus Data Owner` on Service Bus Namespace (Dapr pub/sub)
   - `Key Vault Secrets Officer` on Key Vault (Dapr secrets)

3. **Handles idempotency gracefully** — if a role assignment already exists, logs and skips it

4. **Provides clear logging** — shows which roles were assigned and to which resources

The function is called automatically after `rad deploy` succeeds, with no additional configuration needed.

## Design Notes

### Why Radius recipes don't assign RBAC roles

Radius recipes are **infrastructure templates** that provision Azure resources. They intentionally do not assign RBAC roles because:

- RBAC role scopes are defined at the resource group / subscription level, which is outside recipe scope
- Recipes run in **recipe execution mode**, where they don't have permissions to create role assignments
- Role assignment is a **platform-level concern**, not a recipe concern — it's the responsibility of the platform layer (bootstrap script) that orchestrates recipes

### Why bootstrap now owns this

The bootstrap script is the **orchestration layer** that:
- Manages subscription, resource group, and workspace setup
- Registers Radius credentials (which include the managed identity)
- Deploys the Radius application (which triggers recipe execution)
- Now: Assigns RBAC roles after recipes complete

This follows the separation of concerns: recipes provision, bootstrap orchestrates and configures.

### Idempotency design

The function is safe to run repeatedly because:

1. **Resource queries are idempotent** — querying the resource group for resources matching a naming pattern always returns the same resources (or none, if recipes haven't run yet)

2. **Role assignment creation is idempotent** — Azure CLI returns success if the role is already assigned; if assignment fails, the function checks whether it already exists before warning

3. **No state mutations** — function only reads and assigns; doesn't delete or modify existing resources

This means:
- Running bootstrap twice with the same inputs assigns roles once and skips on the second run
- If RBAC assignment fails midway, re-running bootstrap completes it
- Dry-run mode does not execute role assignments (respects `DRY_RUN` flag)

## Integration Points

- **Triggered after:** `rad_deploy_with_recovery` completes successfully
- **Before:** GHCR pull secret wiring (non-blocking dependency)
- **Uses:** Cached variables: `$AZURE_SUBSCRIPTION_ID`, `$RESOURCE_GROUP`, `$AZURE_PRINCIPAL_ID_CACHED`
- **Logs via:** Standard platform-common.sh functions: `log_info`, `log_success`, `log_warning`, `log_error`

## Testing Scenarios

1. **First run** — all role assignments succeed, logs show 3 roles assigned
2. **Second run** — all role assignments already exist, logs show idempotent behavior
3. **Partial failure** — if one role assignment fails but others succeed, function continues and logs warnings
4. **No recipes deployed** — if no recipe resources exist yet, function reports no changes needed
5. **Dry run** — role assignments do not execute; `--dry-run` flag is respected

## Future Considerations

- Consider whether other Radius resources (e.g., Dapr stateStores, pubSubBrokers) need post-deployment RBAC configuration
- Monitor Azure role assignment limits if scaling to many resources per deployment
- Consider caching role assignment checks if bootstrap performance becomes an issue

---

**Status:** ✅ Complete — function implemented, tested, and integrated into bootstrap flow

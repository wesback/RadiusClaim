# Session Log: spn-catchtwentytwo

**Date:** 2026-03-27  
**Time:** 09:38:00Z  
**Agent:** Pete (Infrastructure Automation Specialist)  
**Task:** Fix catch-22 in prepare-cluster.sh — SPN environment variables blocking role assignment

## Problem Statement

The `scripts/prepare-cluster.sh` script was failing when trying to assign the Contributor role to a newly created Azure service principal. The failure occurred because:

1. Azure CLI environment variables (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`) were set in the shell
2. This causes `az` to authenticate **as the SPN** for all subsequent commands
3. The SPN doesn't have `Microsoft.Authorization/roleAssignments/write` permission
4. Therefore, `az role assignment create` fails with a 403 authorization error

This is a catch-22: we need to assign the Contributor role to the SPN before it can do anything else, but we can't assign the role as the SPN itself.

## Solution Implemented

Modified `scripts/prepare-cluster.sh` to temporarily unset the SPN environment variables before running privileged Azure CLI operations:

### Location 1: Resource Group Creation (Lines 172–184)

When reusing an existing SPN, the script creates a resource group. This operation requires the user's identity, not the SPN's.

```bash
# Save SPN env vars
local saved_client_id="${AZURE_CLIENT_ID:-}"
local saved_client_secret="${AZURE_CLIENT_SECRET:-}"
local saved_tenant_id="${AZURE_TENANT_ID:-}"

# Unset so az uses user's own login
unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID

# Create resource group as user
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" ...

# Restore SPN env vars for later SPN-scoped operations
export AZURE_CLIENT_ID="$saved_client_id"
export AZURE_CLIENT_SECRET="$saved_client_secret"
export AZURE_TENANT_ID="$saved_tenant_id"
```

### Location 2: Role Assignment (Lines 388–420)

After creating a new SPN, the script assigns the Contributor role. This must run as the user's identity.

```bash
# Save SPN env vars
local saved_client_id="${AZURE_CLIENT_ID:-}"
local saved_client_secret="${AZURE_CLIENT_SECRET:-}"
local saved_tenant_id="${AZURE_TENANT_ID:-}"

# Unset so az uses user's own login
unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID

# Assign Contributor role as user
az role assignment create --assignee "$app_id" --role Contributor --scope "/subscriptions/$sub_id" ...

# Restore SPN env vars for subsequent SPN-scoped operations
export AZURE_CLIENT_ID="$saved_client_id"
export AZURE_CLIENT_SECRET="$saved_client_secret"
export AZURE_TENANT_ID="$saved_tenant_id"
```

## Key Insights

1. **Environment variables are global:** Setting `AZURE_CLIENT_ID` affects **every** `az` command in the shell, not just the ones we intend
2. **Unset is safe:** When these env vars are unset, `az` falls back to credentials from `az login`, which the user has already authenticated with
3. **Symmetric flow:** We save → unset → operate → restore to ensure clean state and predictable behavior
4. **User identity is privileged:** The user who runs `az login` has the permissions needed to create resources and assign roles; the SPN doesn't

## Testing Approach

- Verified the fix by running `scripts/prepare-cluster.sh` with `--create-spn` flag
- Confirmed role assignment completes successfully (no 403 errors)
- Verified that subsequent `rad credential register azure sp` commands work correctly with env vars restored
- Checked that resource group creation (when reusing SPN) also completes successfully

## Follow-up

Captured this pattern as a formal decision in `.squad/decisions/inbox/pete-az-credential-isolation.md` so the team knows:
- When to apply this pattern (any privileged `az` operation while SPN env vars are set)
- How to apply it (save → unset → operate → restore)
- Why it works (user vs. SPN permissions)
- Where it's currently used (prepare-cluster.sh, lines 172–184 and 388–420)

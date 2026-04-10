# Dapr PostgreSQL Authentication Fix

## Problem
The Radius recipe for PostgreSQL state store was configured with **Entra-only authentication** (`passwordAuth: Disabled`), but Dapr's PostgreSQL component does not natively support Azure Entra AD token authentication. This caused Dapr sidecars to fail during component initialization with:

```
failed to ping the database: failed to connect to `user=...`: 
failed SASL auth: FATAL: password authentication failed (SQLSTATE 28P01)
```

## Root Cause
- **Radius recipe** (state-store.bicep): Created PostgreSQL with Entra-only auth
- **Dapr's state.postgresql component**: Does not support the `useAzureAD` metadata or automatic Entra token injection in connection strings
- **App requirement**: Requires Dapr state store for persistence

## Solution
Enable `passwordAuth: 'Enabled'` in the PostgreSQL server configuration alongside Entra auth. This allows both:
- Managed identity authentication (Entra AD tokens) for workloads that support it
- Password-based authentication (local users) for Dapr and other components

## Fix Applied
**File:** `infra/radius/recipes/azure/state-store.bicep` (Line 240)

Changed:
```bicep
passwordAuth: 'Disabled'  // No local passwords
```

To:
```bicep
passwordAuth: 'Enabled'   // REQUIRED: Dapr's PostgreSQL component doesn't support Entra auth natively
```

## Deployment
After this fix is applied, a **full infrastructure rebuild** is required because the existing PostgreSQL server must be deleted and recreated:

```bash
./teardown.sh
./prepare-cluster.sh
./bootstrap.sh
```

The new deployment will:
1. Create PostgreSQL server with both Entra and password auth enabled
2. Register managed identity as Entra admin (for future portability)
3. Bootstrap will create local user credentials for Dapr
4. Dapr components will initialize successfully

## Post-Fix Behavior
- PostgreSQL server allows both Entra and password authentication
- Managed identity (Entra admin) remains configured for future use
- Dapr sidecars authenticate using local user credentials
- App functions normally without further changes
- Expense-api → Dapr statestore → PostgreSQL flow works end-to-end

## Portability Note
This is a **portable fix** that doesn't introduce cloud-specific workarounds:
- Uses standard PostgreSQL authentication mechanisms
- Follows Dapr component configuration patterns
- Can be applied to any cloud provider's PostgreSQL offering

The fix maintains the principle of environment-based configuration: deployment details (auth method) are managed in Radius recipes/parameters, not in app code.

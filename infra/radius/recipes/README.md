# Radius Recipes

This directory contains reusable Bicep recipes for provisioning Azure-backed Dapr components (state store, pub/sub, secrets).

## Architecture

Each recipe:
- Accepts a **context** parameter injected automatically by Radius
- Provisions a specific Azure resource (Blob Storage, Service Bus, Key Vault)
- Returns **values** (connection info) and **resources** (Azure IDs) for Radius lifecycle tracking
- Uses Microsoft Entra **workload identity** for authentication (zero shared keys)

## Resource Naming

### Deterministic Naming (Production)

By default, recipes generate deterministic resource names using `uniqueString(context.resource.id)`:

```
State Store: staterc{suffix}          (Azure Storage Account)
Pub/Sub:     pubsubrc{suffix}         (Azure Service Bus Namespace)
Secrets:     kvrc{suffix}             (Azure Key Vault)
```

This ensures the same resource name is created on every deployment, enabling stable Azure RBAC and access policies.

### Random Naming (Dev/Demo)

For non-production environments, recipes support an optional `randomNameSuffix` parameter to generate unique resource names on each deployment run:

```
randomNameSuffix: a3f9e2  (6-char timestamp-hash, generated at deploy time)

State Store: staterC-a3f9e2
Pub/Sub:     pubsubrc-a3f9e2
Secrets:     kvrc-a3f9e2
```

**Why random naming?**
- Azure soft-deletes resources for 7 days. A re-deployment within that window would collide with the deletion marker.
- Random naming prevents this collision pain, enabling clean demo runs back-to-back.
- Naming still remains readable (base name + short hash) for manual resource lookups.

**When to use?**
- ✅ Dev/demo environments: Apply random naming to avoid soft-delete collisions
- ❌ Production: Use deterministic naming only

## Deployment

### With Random Naming (Dev/Demo)

The `scripts/bootstrap.sh` automatically applies random naming when deploying to `radiusclaim-azure` environment:

```bash
./scripts/bootstrap.sh \
  --resource-group my-rg \
  --env-name radiusclaim-azure
```

The script generates a 6-character timestamp-hash and passes it to all recipes via the `--parameters randomNameSuffix=<value>` flag.

### With Deterministic Naming (Production)

Omit the suffix (or set it to empty) to use `uniqueString` for stable resource names:

```bash
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters randomNameSuffix=
```

## Cleanup

For dev/demo environments, Azure soft-deleted resources accumulate over time. A future enhancement should add a cleanup script to purge old orphaned resources in the subscription.

Example (future):
```bash
./scripts/cleanup-orphaned-resources.sh --subscription-id <id> --prefix staterc --keep-days 7
```

## Recipe Files

- **state-store.bicep** — Azure Blob Storage for Dapr state management
- **pubsub.bicep** — Azure Service Bus for Dapr pub/sub messaging
- **secrets.bicep** — Azure Key Vault for Dapr secret management

## Implementation Notes

- All recipes use RBAC-only authorization (no shared keys or access policies)
- Workload identity credentials are injected by the AKS webhook into Dapr sidecars
- Recipes run in the context of a Radius-provisioned managed identity with appropriate roles
- Azure SDK + Dapr automatically handle token exchange transparently

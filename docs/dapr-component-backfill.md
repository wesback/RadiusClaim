# Dapr Component Backfill: Connecting Apps to Infrastructure

> **Audience:** Developers and operators learning how Radius + Dapr deployments wire app code to Azure backing services  
> **Goal:** Understand why Dapr components are deployed *after* Radius, what the backfill scripts do, and when you need them

---

## The Gap: Infrastructure vs. Application Layer

Radius and Dapr divide responsibilities cleanly:

- **Radius** creates the infrastructure: Azure Storage accounts, Service Bus namespaces, Key Vaults
- **Dapr** provides the app-layer abstractions: statestore, pubsub, secretstore components

But there's a gap: **Radius provisions the backing services, but doesn't automatically project Dapr Component CRDs into your Kubernetes cluster.**

The **Dapr component backfill scripts** bridge this gap. They:
1. Fetch infrastructure outputs from Radius (storage account names, Service Bus endpoints, Key Vault names)
2. Grant the necessary RBAC permissions (Storage Blob Data Contributor, Key Vault Secrets User)
3. Generate Dapr Component YAML manifests with the correct Azure resource references
4. Apply those manifests to your Kubernetes namespace so Dapr sidecars can connect

---

## Why the Two-Step Process?

**Short answer:** Radius creates the infrastructure foundation; the backfill scripts wire apps to that foundation.

**Longer answer:**

When you run `rad deploy`:
- Radius recipes execute (via Bicep templates) to create Azure resources
- Radius generates Kubernetes Deployment manifests for your containers
- Your pods start, with Dapr sidecars injected

But the Dapr sidecars **cannot** connect to Azure Storage or Service Bus yet—the Dapr Component definitions don't exist in the cluster.

The backfill step:
- Reads what Radius created (via `rad resource show`)
- Translates those outputs into Dapr-compatible component specs
- Applies them to the cluster so sidecars can authenticate and connect

**Result:** Your app code (using Dapr SDK) can now call `statestore`, `pubsub`, and `platform-secrets` without knowing they're backed by Azure Blob, Service Bus, and Key Vault.

---

## What the Backfill Scripts Do

RadiusClaim includes two backfill scripts. The **workload identity variant** is the current, recommended path.

### `deploy-dapr-components-workload-identity.sh` (Current)

**Purpose:** One-time cluster bootstrap for workload identity, then repeatable component projection.

**What it does:**

1. **Enable workload identity on AKS** (if `--setup-workload-identity` passed):
   - Enables OIDC issuer and workload identity addon
   - Creates a user-assigned managed identity (`radiusclaim-workload-identity`)
   - Configures federated identity credentials for Kubernetes service accounts

2. **Fetch Radius outputs:**
   ```bash
   rad resource show Applications.Dapr/stateStores statestore -a radiusclaim -o json
   rad resource show Applications.Dapr/pubSubBrokers pubsub -a radiusclaim -o json
   rad resource show Applications.Dapr/secretStores platform-secrets -a radiusclaim -o json
   ```

3. **Grant RBAC permissions** to the managed identity:
   - `Storage Blob Data Contributor` on the storage account
   - `Key Vault Secrets User` on the Key Vault

4. **Generate Dapr component manifests** with Microsoft Entra authentication:
   - `statestore` → `state.azure.blobstorage` with `azureClientId`, `azureTenantId`
   - `pubsub` → `pubsub.azure.servicebus.topics` with connection string (from Kubernetes secret)
   - `platform-secrets` → `secretstores.azure.keyvault` with `azureClientId`, `azureTenantId`

5. **Apply to cluster:**
   ```bash
   kubectl apply -f dapr-components-generated.yaml
   ```

6. **Verify components are live:**
   ```bash
   kubectl get components -n radiusclaim-azure-radiusclaim
   ```

**When to run:** 
- First deployment: Requires `--setup-workload-identity` to configure AKS and create the managed identity
- Subsequent deployments: Runs automatically as part of `bootstrap.sh` to refresh components after infrastructure changes

### `deploy-dapr-components.sh` (Deprecated — Do Not Use)

**Status:** Removed from active use. Do not use for new deployments.

**Why it's deprecated:** This script generated Dapr components using service principal authentication (client secrets), which:
- Stores sensitive credentials in Kubernetes secrets
- Does not align with the zero-secrets deployment model
- Is not compatible with Azure Policy blocking shared-key authentication
- Has been replaced by the workload identity approach for better security

**All new deployments must use `deploy-dapr-components-workload-identity.sh`.**

---

## When the Backfill Runs

### Automatic: Part of Bootstrap

The recommended deployment path (`scripts/bootstrap.sh`) includes the backfill as an integrated step:

```bash
./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
```

Bootstrap workflow:
1. Publish Radius recipes to container registry
2. Deploy Radius environment (`azure-radius.bicep`)
3. Deploy Radius application (`app.bicep`)
4. **→ Backfill Dapr components** (calls `deploy-dapr-components-workload-identity.sh`)
5. Validate deployment (check endpoints, sidecars, components)

The backfill step is **idempotent**—safe to run multiple times. If components already exist, it updates them in place.

### Manual: Troubleshooting or Recovery

You can run the backfill script directly if you need to:
- Refresh components after changing Radius infrastructure
- Recover from a failed component deployment
- Test workload identity configuration

```bash
# With workload identity (no client secret needed)
./scripts/deploy-dapr-components-workload-identity.sh \
  --resource-group radiusclaim-rg \
  --setup-workload-identity  # Only needed first time

# Dry run to preview generated YAML
./scripts/deploy-dapr-components-workload-identity.sh \
  --resource-group radiusclaim-rg \
  --dry-run
```

**Prerequisite:** Radius app must already be deployed (`rad deploy` succeeded). The script reads infrastructure names from Radius resource outputs.

---

## What You Should See

After the backfill succeeds, verify components are available:

```bash
kubectl get components -n radiusclaim-azure-radiusclaim
```

Expected output:
```
NAME               AGE
platform-secrets   2m
pubsub             2m
statestore         2m
```

Check Dapr sidecar logs to confirm components loaded:

```bash
kubectl logs -n radiusclaim-azure-radiusclaim deployment/expense-api -c daprd | grep "component loaded"
```

Expected:
```
component loaded. name: statestore, type: state.azure.blobstorage
component loaded. name: pubsub, type: pubsub.azure.servicebus.topics
component loaded. name: platform-secrets, type: secretstores.azure.keyvault
```

---

## Key Takeaways

1. **Radius creates infrastructure; Dapr components wire apps to it.**  
   The backfill scripts translate Radius outputs into Dapr-compatible CRDs.

2. **Workload identity is the current path.**  
   No client secrets needed—federated credentials handle Azure authentication.

3. **Bootstrap handles it automatically.**  
   Use `scripts/bootstrap.sh` for the full deployment. The backfill is integrated.

4. **Safe to rerun.**  
   The script is idempotent—updates components in place if they exist.

5. **Manual runs are for recovery.**  
   If components fail to load or you change infrastructure, rerun the script directly.

---

## Further Reading

- **End-to-end setup:** [docs/end-to-end-setup-walkthrough.md](./end-to-end-setup-walkthrough.md) — Full deployment guide
- **Bootstrap script details:** [scripts/README.md](../scripts/README.md) — What each script does
- **Workload identity deep dive:** [Microsoft Docs](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) — How federated credentials work

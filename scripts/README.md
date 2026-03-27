# RadiusClaim - Scripts

This directory contains operational, setup, and validation scripts for RadiusClaim.

---

## Script Workflow

**For first-time deployment:**
1. **Cluster Prep** (`prepare-cluster.sh`) — Verifies or creates AKS, sets `kubectl` context, installs/verifies Dapr + Radius, and selects the Radius workspace/group
2. **App Bootstrap** (`bootstrap.sh`) — Deploys RadiusClaim app and validates on the prepared cluster

**For iterative development or re-deployments:**
- Use `bootstrap.sh` alone (assumes cluster is already prepared)

---

## Available Scripts

### `prepare-cluster.sh` (First-Time Cluster Setup)

**Purpose:** Prepare a Kubernetes cluster for the first deployment boundary (AKS reuse/create, `kubectl` context, Dapr, Radius, and Radius workspace/group).

**What it does:**
- Verifies Azure login/subscription
- Reuses or creates the Azure resource group used later by `bootstrap.sh`
- Reuses or creates an AKS cluster only when explicitly allowed
- Sets or verifies the `kubectl` context
- Installs Dapr control plane when requested, otherwise verifies it
- Installs Radius control plane when requested, otherwise verifies it
- Selects the Radius workspace and group used by later `rad deploy` commands

**When to use:**
- First deployment on a new cluster
- Re-validating cluster readiness before handing the environment to `bootstrap.sh`

**Usage:**
```bash
./scripts/prepare-cluster.sh \
  --resource-group <name> \
  [--location <azure-region>] \
  [--aks-cluster-name <name>] \
  [--create-aks] \
  [--install-dapr] \
  [--install-radius] \
  [--yes]
```

> **Fresh cluster note:** If the target cluster does not already have Dapr and Radius, include both `--install-dapr` and `--install-radius`. Omitting those flags puts the script in verification-only mode for the control planes, so it will stop instead of installing them.

**Example:**
```bash
./scripts/prepare-cluster.sh \
  --resource-group radiusclaim-rg \
  --location belgiumcentral \
  --aks-cluster-name radiusclaim-aks \
  --create-aks \
  --install-dapr \
  --install-radius \
  --yes
```

**Notes:**
- Requires `az`, `kubectl`, `dapr`, `rad`, and `jq`
- `--resource-group` is required because the same Azure scope is reused by `bootstrap.sh`
- Defaults to verification/reuse; AKS creation requires the explicit `--create-aks` gate
- First-time prep on a fresh cluster should include `--install-dapr --install-radius`; otherwise the script only verifies existing control planes
- Existing Arc-enabled or self-managed clusters can skip AKS flags, but must provide a working current `kubectl` context (or `--kube-context`)
- Idempotent-safe: reuses existing AKS clusters and control planes instead of recreating them
- Default location: `belgiumcentral` per team directive
- AKS creation typically takes 10–15 minutes

**After success:**
Run `./scripts/bootstrap.sh --resource-group <name>` to deploy the RadiusClaim application.

---

### `bootstrap.sh` (App Deployment & Component Backfill)

**Purpose:** Deploy the RadiusClaim application, Dapr components, and validate the deployment (replaces manual Steps 7–12 of the end-to-end walkthrough). **Assumes cluster is already prepared** with `prepare-cluster.sh` or equivalent manual setup.

**When to use:**
- After `prepare-cluster.sh` completes (or for re-deployments to an existing cluster)
- For repeatable application deployments and updates

**What it wraps:**
- `publish-radius-recipes.sh` for OCI recipe publication
- `deploy-dapr-components-workload-identity.sh` for cluster-level workload identity bootstrap (first deploy only)
- `validate-deployment.sh` for post-deployment smoke testing

**What it adds:**
- Pre-flight checks: CLIs, Azure login, prepared Kubernetes cluster health, Dapr/Radius control planes ready
- Idempotent Radius workspace/environment setup
- Interactive confirmations before resource creation and credential registration (`--yes` for non-interactive)
- Truthful Azure Key Vault soft-delete handling for the Azure-backed `platform-secrets` store (restore when safe, fail early when not)
- Automatic Dapr component backfill and pod restart verification

**Usage:**
```bash
./scripts/bootstrap.sh --resource-group <name> [options]
```

**Example:**
```bash
./scripts/bootstrap.sh \
  --resource-group radiusclaim-rg \
  --yes
```

**Prerequisites:**
- Cluster prepared with Dapr and Radius (via `prepare-cluster.sh` or manual setup)
- Azure resource group exists (created by `prepare-cluster.sh` or Step 2 of manual walkthrough)
- `az`, `kubectl`, `rad` CLIs installed and configured
- **Microsoft Entra authentication** variables for the state-store recipe:
  - `AZURE_CLIENT_ID` — Application/service principal client ID
  - `AZURE_TENANT_ID` — Azure tenant ID
  - `AZURE_PRINCIPAL_ID` — Principal object ID (auto-resolved from service principal if not set; see *Principal ID Resolution* below)
  - `AZURE_CLIENT_SECRET` — Only required when using service principal auth (not workload identity)
- **RBAC Permissions:** The authenticated identity needs:
  - **Contributor** role on the resource group (for creating resources)
  - **User Access Administrator** role on the resource group (for assigning data-plane roles in recipes)
  
  Bootstrap automatically grants **User Access Administrator** when `AZURE_PRINCIPAL_ID` is available. If you're using a service principal that already has these roles, no manual action is needed.

**Principal ID Resolution:**

Bootstrap requires `AZURE_PRINCIPAL_ID` (principal object ID) for RBAC assignments to Azure Blob storage. It resolves this automatically by:
1. Using `AZURE_PRINCIPAL_ID` if explicitly set
2. Running `az ad sp show --id "$AZURE_CLIENT_ID"` if `AZURE_CLIENT_ID` is set
3. Failing with actionable diagnostics if resolution fails

**If auto-resolution fails**, you're likely using:
- **User identity** — Set `export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)`
- **Managed identity** — Set `export AZURE_PRINCIPAL_ID=<managed-identity-object-id>`

See the `deploy-dapr-components.sh` prerequisites section for more detail on supported auth modes.


**Notes:**
- By default derives image and recipe tags from the current git SHA
- Use `./scripts/bootstrap.sh --help` for all options: `--skip-recipes`, `--skip-image-push`, `--skip-validation`, `--image-platform`, `--validation-url`
- Idempotent: safe to re-run for updates
- If the deterministic `platform-secrets` Key Vault name is still soft-deleted, bootstrap now checks that before `rad deploy infra/radius/app.bicep`; it restores the vault when Azure can safely recover it back into the current resource group, otherwise it stops with actionable guidance instead of letting the app deploy fail unclearly

### `publish-radius-recipes.sh`

**Purpose:** Publish the repo's custom Radius recipes to an OCI registry before deploying an environment that references them.

**Usage:**
```bash
./scripts/publish-radius-recipes.sh <recipe-registry> <tag>
```

**Example:**
```bash
# For GHCR with explicit auth (either variable name works)
export GHCR_TOKEN="your_github_pat_with_write_packages_scope"
export GHCR_USERNAME="your-github-username"  # or GITHUB_USERNAME

# If already authenticated via docker login
docker login ghcr.io
./scripts/publish-radius-recipes.sh ghcr.io/your-username/radiusclaim/recipes local
```

**Authentication:**

For **ghcr.io** registries, the script supports three authentication modes:

1. **Environment variables** (recommended for automation):
   ```bash
   export GHCR_TOKEN="ghp_..."  # GitHub PAT with 'write:packages' scope
   export GHCR_USERNAME="your-github-username"  # or use GITHUB_USERNAME
   ```
   Username fallback order: `GHCR_USERNAME` → `GITHUB_USERNAME` → `GITHUB_ACTOR` → `git config user.name`

2. **Pre-authenticated docker** (manual workflow):
   ```bash
   echo "$TOKEN" | docker login ghcr.io --username YOUR_USERNAME --password-stdin
   # Then run publish script
   ```

3. **Interactive docker login**:
   ```bash
   docker login ghcr.io  # Prompts for credentials
   ```

For **non-GHCR registries**, set:
```bash
export REGISTRY_USERNAME="..."
export REGISTRY_PASSWORD="..."
```

**Error Handling:**

If publishing fails with a 403 error, the script provides actionable diagnostics:
- Missing or invalid authentication
- Insufficient token permissions (needs 'write:packages')
- Namespace mismatch (package path doesn't match your GitHub username/org)

**Why it exists:**
- Radius recipe `templatePath` values must resolve to OCI-backed artifacts, not local relative files
- The script keeps the three custom recipes (`state-store`, `pubsub`, `secrets`) published under one teachable command
- GitHub Actions reuses the same script with `GHCR_TOKEN` and `GHCR_USERNAME` from workflow secrets

### `deploy-dapr-components-workload-identity.sh` (Cluster Bootstrap — One-Time)

> ⚠️ **Scope:** This is a **cluster bootstrap script**, not a per-deployment script. After this script runs once on a cluster, `rad deploy` handles Dapr Component CRD projection automatically via the Radius application model.

**Background:** Radius projects Dapr Component CRDs (`statestore`, `pubsub`, `platform-secrets`) automatically during `rad deploy` when workload identity parameters (`daprAzureClientId`, `daprAzurePrincipalId`) are supplied to the `azure-radius.bicep` environment recipe. The recipes assign RBAC and emit the component metadata; Radius materializes the Kubernetes CRDs.

This script is required **once per cluster** to configure AKS-level infrastructure that Radius recipes cannot express:
1. Enable OIDC issuer + workload identity addon on AKS
2. Create the user-assigned managed identity
3. Create federated identity credentials per service account
4. Annotate Kubernetes service accounts with `azure.workload.identity/client-id`

**Usage:**
```bash
./scripts/deploy-dapr-components-workload-identity.sh \
  --resource-group <rg> \
  --setup-workload-identity \
  [--cluster-name <name>] \
  [--dry-run]
```

**After bootstrap:** Record the managed identity `clientId` and object ID in `infra/radius/environments/azure-radius.parameters.json` as `daprAzureClientId` / `daprAzurePrincipalId`. Subsequent `rad deploy` runs project CRDs automatically — this script is not needed again unless the cluster or managed identity is recreated.

---

### `deploy-dapr-components.sh` (Deprecated)

> ⚠️ **Deprecated:** Use `deploy-dapr-components-workload-identity.sh` for cluster bootstrap, then let `rad deploy` handle CRD projection. This script uses Service Principal auth with connection strings and is retained only as a reference fallback.

**Purpose:** Backfill Dapr Component CRDs into Kubernetes. Kept as emergency fallback only.

**Usage:**
```bash
./scripts/deploy-dapr-components.sh --resource-group <rg> [OPTIONS]
```

**Options:**
| Flag | Description | Default |
|------|-------------|---------|
| `--resource-group <name>` | Azure resource group (required) | — |
| `--app-name <name>` | Radius application name | `radiusclaim` |
| `--env-name <name>` | Radius environment name | `azure` |
| `--namespace <name>` | Kubernetes workload namespace | Auto-detected |
| `--dry-run` | Generate YAML without applying | `false` |

**Example:**
```bash
# Auto-detect workload namespace from Radius environment
./scripts/deploy-dapr-components.sh --resource-group radiusclaim-rg

# Explicit namespace
./scripts/deploy-dapr-components.sh \
  --resource-group radiusclaim-rg \
  --namespace radiusclaim-azure-radiusclaim

# Dry run (review YAML before applying)
./scripts/deploy-dapr-components.sh \
  --resource-group radiusclaim-rg \
  --dry-run
# Then review: cat dapr-components-generated.yaml
```

**What it does:**
1. Reads Radius resource metadata to find Azure backing-resource names
2. Repairs the Azure data-plane RBAC needed by the backfilled Blob/Key Vault components
3. Fetches runtime credentials (Microsoft Entra client secret when present, Service Bus connection string)
4. Creates Kubernetes secrets in the workload namespace
5. Generates and applies Dapr Component manifests (`statestore`, `pubsub`, `platform-secrets`)

**Prerequisites:**
- `rad` CLI (Radius app must be deployed first)
- `kubectl` (cluster access)
- `az` CLI (Azure credentials configured)
- `jq` (JSON processing)
- **Microsoft Entra authentication** for the Blob statestore:
  - `AZURE_CLIENT_ID` — Application/service principal client ID
  - `AZURE_TENANT_ID` — Azure tenant ID
  - `AZURE_PRINCIPAL_ID` — Principal object ID (see below if not set)
  - `AZURE_CLIENT_SECRET` — Only required when using service principal auth (not workload identity)

**About AZURE_PRINCIPAL_ID:**

The Entra-backed Dapr statestore requires the principal's **object ID** (not the client ID) for RBAC role assignments.

The script attempts to resolve this automatically:
1. If `AZURE_PRINCIPAL_ID` is set → uses that value directly
2. If `AZURE_CLIENT_ID` is set → tries `az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv`
3. If resolution fails → stops with actionable diagnostics

**When to set AZURE_PRINCIPAL_ID manually:**
- **User identity mode:** If you're using `az login` with a user identity instead of a service principal, set:
  ```bash
  export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
  ```
- **Managed identity mode:** If using a managed identity for Dapr runtime auth, provide its object ID:
  ```bash
  export AZURE_PRINCIPAL_ID=<managed-identity-object-id>
  ```
- **Service principal without auto-resolution:** If `az ad sp show` fails but you know the object ID, set it directly.

**Supported auth modes:**
- ✅ Service principal (client ID + secret)
- ✅ Workload identity (federated credential without secret)
- ✅ User identity (interactive `az login` with manual `AZURE_PRINCIPAL_ID`)
- ✅ Managed identity (with manual `AZURE_PRINCIPAL_ID`)


**Output:**
- `dapr-components-generated.yaml` in the repo root (generated manifest for review)
- Dapr Component CRDs applied to the workload namespace
- Exit code 0 on success, non-zero on failure (see script header for codes)

### `validate-deployment.sh`

**Purpose:** End-to-end validation script for deployed RadiusClaim instances on Kubernetes.

**What it validates:**
- API health endpoint accessibility
- $50 auto-approve flow (complete state transitions)
- $150 manual-review flow (hold, not rejection)
- $100.00 boundary case (manual review, not auto-approval)
- Distributed system behavior (state, workflow, service invocation)

**Usage:**
```bash
./scripts/validate-deployment.sh <expense-api-base-url>
```

**Example (local port-forward for Kubernetes):**
```bash
# Set up port-forward to expense-api (use WORKLOAD namespace, not environment namespace)
kubectl port-forward -n radiusclaim-azure-radiusclaim svc/expense-api 8080:8080 &

# Run validation against the forwarded port
./scripts/validate-deployment.sh http://127.0.0.1:8080
```

**Example (if expense-api has external ingress):**
```bash
./scripts/validate-deployment.sh https://expense-api.example.com
```

**Prerequisites:**
- `jq` installed (JSON processing)
- `curl` installed (HTTP requests)
- RadiusClaim deployed to Kubernetes and accessible (either via port-forward or external ingress)

**Output:**
- Colored pass/fail indicators for each check
- Summary of total checks passed/failed
- Exit code 0 on success, 1 on failure

**Use cases:**
- Post-deployment smoke test
- Manual validation before demo
- CI/CD integration (already integrated in `.github/workflows/deploy-azure.yml`)
- Troubleshooting deployment issues

**Optional CI artifact:**
- Set `VALIDATION_OUTPUT_PATH=/path/to/results.json` to capture expense and correlation IDs for downstream log checks
- The GitHub Actions workflow uses this to pair the shared flow validation with platform-specific notification evidence

**What this proves:**
- The sample demonstrates **meaningful distributed behavior**, not just process startup
- State persistence works across Dapr components
- Workflow orchestration executes correctly
- Service-to-service invocation delivers workflow requests
- Approval thresholds are implemented correctly
- Boundary case is handled as documented

---

## Adding New Scripts

When adding scripts to this directory:

1. **Use descriptive names:** `validate-*`, `deploy-*`, `troubleshoot-*`
2. **Add executable permission:** `chmod +x scripts/your-script.sh`
3. **Include usage documentation:** Header comment with purpose, usage, prerequisites
4. **Update this README:** Add entry in "Available Scripts" section
5. **Validate syntax:** Run `bash -n scripts/your-script.sh` before committing

---

## Script Conventions

- **Error handling:** Use `set -euo pipefail` for strict error handling
- **Output clarity:** Use colored output for pass/fail indicators
- **Exit codes:** 0 for success, non-zero for failure
- **Portability:** Bash 4.0+ compatible, avoid GNU-specific extensions
- **Documentation:** Clear usage message when run without arguments

---

## Integration Points

### GitHub Actions

The `validate-deployment.sh` script logic is integrated into `.github/workflows/deploy-azure.yml`:
- Run automatically after every deployment
- Reuses the same flow validation for the Kubernetes-first Radius path
- Uses `kubectl port-forward` plus `kubectl logs` after the shared script so the workflow stays valid across AKS, Arc-enabled / Azure Local, and self-managed Kubernetes clusters that meet Radius prerequisites
- Keeps the portability story honest: compute is Kubernetes-portable, but the current backing-service recipes remain Azure-specific
- Fails the workflow if validation does not pass

### Phase Gates

Validation scripts support phase gate approvals:
- Karen (Tester) runs scripts to validate phase completion
- Script output provides fresh evidence for gate reviews
- Pass/fail outcomes inform approval decisions

---

## Troubleshooting

### Script hangs during status polling

**Cause:** Service may be slow to start or networking issue  
**Solution:** Check workload health with `kubectl get deploy,pods -n <namespace>` and increase wait timeout if needed

### jq not found

**Cause:** jq not installed  
**Solution:** Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- Windows: Download from https://stedolan.github.io/jq/

### curl: Failed to connect

**Cause:** Incorrect URL or service not accessible  
**Solution:** Verify the expense-api URL or `kubectl port-forward` session, check cluster networking rules, and confirm the service is running

### All checks fail with "Failed to reach health endpoint"

**Cause:** Service not deployed or networking issue  
**Solution:** 
1. Verify deployment completed: `kubectl get deployment expense-api -n <namespace>`
2. Check service exposure: `kubectl get svc expense-api -n <namespace>` and port-forward if needed
3. Test health endpoint manually: `curl http://127.0.0.1:8080/healthz` (or your cluster-specific URL)

### bootstrap.sh stops on a soft-deleted `platform-secrets` Key Vault

**Cause:** Azure Key Vault names stay reserved while a vault is in soft-delete. RadiusClaim uses a deterministic vault name for the Azure-backed `platform-secrets` store, so a deleted vault can block repeat deployments.

**What bootstrap does now:**
1. Resolves the exact Key Vault name Radius will use for `platform-secrets`
2. Checks whether that vault is active, soft-deleted, or unavailable
3. Restores it automatically after confirmation when Azure can recover it back into the current subscription/resource-group/location
4. Fails early with the conflicting scope and purge guidance when Azure can only recover it somewhere else

**If bootstrap still stops:**
- Restore or purge the deleted vault manually if you own the original scope
- Or use a different Radius environment name so the deterministic vault name changes

---

## References

- End-to-End Setup Walkthrough: [`docs/end-to-end-setup-walkthrough.md`](../docs/end-to-end-setup-walkthrough.md)
- Phase 7 Validation Checklist: [`docs/phase-7-validation-checklist.md`](../docs/phase-7-validation-checklist.md)
- Demo Walkthrough: [`docs/phase-7-demo-walkthrough.md`](../docs/phase-7-demo-walkthrough.md)
- GitHub Actions Workflow: [`.github/workflows/deploy-azure.yml`](../.github/workflows/deploy-azure.yml)

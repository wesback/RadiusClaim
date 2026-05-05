# End-to-End Setup: From Resource Group to Web Browser

> **Audience:** Platform engineers and operators deploying RadiusClaim to Azure  
> **Duration:** ~30–45 minutes (AKS creation), ~5 minutes if cluster exists  
> **Goal:** Deploy the complete RadiusClaim stack, then open the web UI in a browser

---

## Overview & Recommended Path

This guide shows you the **fastest, most reliable way** to deploy RadiusClaim: **two shell scripts** that wrap the entire deployment.

### The Happy Path: Two Scripts

RadiusClaim is designed to deploy via **two scripts** that handle the full workflow:

| Script | Purpose | Time | Who Runs It |
|--------|---------|------|------------|
| **`scripts/prepare-cluster.sh`** | Create/verify AKS, install Dapr & Radius, set up Kubernetes context | ~15–20 min | Run once per cluster |
| **`scripts/bootstrap.sh`** | Deploy recipes, Radius environment, RadiusClaim app, validate | ~5–10 min | Run for each deploy/update |

**First deployment:**
```bash
# Step 1: Prepare cluster (one time, or when cluster is fresh)
./scripts/prepare-cluster.sh \
  --resource-group radiusclaim-rg \
  --location belgiumcentral \
  --aks-cluster-name radiusclaim-aks \
  --create-aks \
  --create-spn \
  --install-dapr \
  --install-radius \
  --yes

# Step 2: Deploy the app (repeatable for updates)
# Requires Azure credentials — see "Environment Variables" in the Quick Start below
./scripts/bootstrap.sh \
  --resource-group radiusclaim-rg \
  --create-spn \
  --yes
```

> **Workload Identity (Default & Recommended):** Workload identity is the **default and only supported authentication mode** for RadiusClaim. When you provide `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` (without `AZURE_CLIENT_SECRET`), bootstrap automatically enables workload identity on the AKS cluster. No secrets are stored in the cluster. Shared-key authentication is blocked by Azure Policy and not supported.

**Subsequent deployments (cluster already ready):**
```bash
./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
```

> **Note for macOS users:** If building on Apple Silicon (arm64) for an amd64 AKS cluster, bootstrap auto-detects the mismatch and sets `--image-platform linux/amd64` automatically. You may also pass it explicitly: `--image-platform linux/amd64`.

**That's it.** No manual `az` commands, no `rad` CLI orchestration, no hand-written YAML. The scripts validate, configure, and deploy everything.

---

## When to Use This Guide

- **First deployment?** Start with [Quick Start](#quick-start-run-the-two-scripts) below.
- **Need to customize or debug?** Read [Understanding the Scripts](#understanding-the-scripts) to see what each does.
- **Prefer manual control or learning the internals?** See [Manual Walkthrough (Deep Dive)](#manual-walkthrough-deep-dive) at the end.
- **Using GitHub Actions instead?** Jump to [CI/CD Alternative Path](#cicd-alternative-path).

---

## Prerequisites

Before you start, confirm you have the basic tools:

### For Script-Based Deployment Path (Recommended)
- **Azure CLI** — for authentication and resource creation
- **git** — to clone this repository
- **bash** — to run the scripts
- Azure subscription with permissions to create AKS clusters, resource groups, and role assignments
- Roughly 15–20 minutes and AKS quota in your target region

### Additional Tools (auto-checked by scripts)
The scripts verify you have:
- **kubectl** — Kubernetes CLI
- **dapr** — Dapr CLI
- **rad** — Radius CLI
- **jq** — JSON processor
- **docker** — for building images (if not using GitHub Actions)
- **gh** (optional) — GitHub CLI; if authenticated, bootstrap auto-populates GHCR credentials. If not present, you can set `GHCR_TOKEN` and `GHCR_USERNAME` manually (see [Troubleshooting GHCR Auth](#troubleshooting-ghcr-auth))

### For CI/CD Path (GitHub Actions)
- Git repository on GitHub with Actions enabled
- Azure subscription credentials configured as GitHub Secrets (see [CI/CD Alternative Path](#cicd-alternative-path))

---

## Quick Start: Run the Two Scripts

### Step 1: Prepare Your Cluster (First Time Only)

Run this once to create or verify your AKS cluster and install Dapr + Radius:

```bash
./scripts/prepare-cluster.sh \
  --resource-group radiusclaim-rg \
  --location belgiumcentral \
  --aks-cluster-name radiusclaim-aks \
  --create-aks \
  --create-spn \
  --install-dapr \
  --install-radius \
  --yes
```

**What happens:**
- ✅ Azure login verified
- ✅ Resource group created (if missing)
- ✅ AKS cluster created or reused (need `--create-aks` first time)
- ✅ kubectl context configured
- ✅ Dapr control plane installed
- ✅ Radius control plane installed
- ✅ Kubernetes workspace/group initialized

**Options for existing clusters:**
- If reusing an **existing AKS cluster**, omit `--create-aks`
- If using **Arc-enabled or self-managed Kubernetes**, omit the AKS flags and ensure `kubectl` points to your cluster (or use `--kube-context`)

### Set Azure Credentials (Only if bringing your own credentials)

> **Quick Start:** If using the default Step 2 command with `--create-spn`, **skip this section**. Bootstrap creates a brand-new service principal and exports all needed credentials automatically — no setup required.

This section applies only when you're bringing your own existing Azure credentials (no `--create-spn`). Bootstrap needs these to wire up backing services and RBAC.

**Workload Identity (Recommended & Default):**

Workload identity is the recommended authentication mode. It uses Azure Entra ID's OIDC federated credentials to authenticate pods without storing secrets in the cluster.

```bash
export AZURE_CLIENT_ID="<managed-identity-client-id>"
export AZURE_TENANT_ID="<your-azure-tenant-id>"
# Note: Do NOT set AZURE_CLIENT_SECRET for workload identity mode

# On fresh clusters, bootstrap auto-detects workload identity mode and enables OIDC issuer + add-ons:
./scripts/bootstrap.sh \
  --resource-group radiusclaim-rg \
  --yes

# Or explicitly request workload identity setup (idempotent, safe on existing clusters):
./scripts/bootstrap.sh \
  --resource-group radiusclaim-rg \
  --setup-workload-identity \
  --yes
```

**What happens automatically:**
- OIDC issuer is enabled on the AKS cluster
- Workload identity addon is installed
- Federated identity credentials link Kubernetes service accounts to the managed identity
- Dapr components use OIDC token exchange — **no secrets stored in the cluster**

<details>
<summary>Service Principal Auth (legacy, not recommended)</summary>

Service principal authentication is **not recommended** and **not supported** in tenant environments with Azure Policy blocking shared-key authentication.

If you must use service principal auth (e.g., legacy systems):
```bash
export AZURE_CLIENT_ID="<service-principal-app-id>"
export AZURE_CLIENT_SECRET="<service-principal-client-secret>"
export AZURE_TENANT_ID="<your-azure-tenant-id>"
export AZURE_PRINCIPAL_ID="<service-principal-object-id>"
```

**Important:** This mode stores the client secret in Kubernetes secrets and is not compatible with tenant policies that block shared-key or secret-based authentication.

</details>

<details>
<summary>User Identity (az login)</summary>

If using 'az login' with your personal Azure account:
```bash
export AZURE_PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"
```

</details>

### Step 2: Deploy the Application

After cluster prep completes and credentials are set, deploy RadiusClaim:

```bash
./scripts/bootstrap.sh \
  --resource-group radiusclaim-rg \
  --create-spn \
  --yes
```

> When `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` are set (without `AZURE_CLIENT_SECRET`), bootstrap automatically enables workload identity on the AKS cluster and configures all prerequisites. Workload identity is the **default and recommended** authentication mode. Shared-key authentication is not supported.

**What happens:**
- ✅ Pre-flight checks (CLIs, Azure auth, cluster health)
- ✅ Radius workspace/environment initialized
- ✅ Recipes published to OCI registry (if needed)
- ✅ Radius environment deployed (Azure backing services wired)
- ✅ RadiusClaim application deployed
- ✅ Dapr components backfilled (state store, pub/sub, secrets)
- ✅ Deployment validated end-to-end
- ✅ Public URL printed to console

**For subsequent deployments** (when cluster is already ready):
```bash
./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
```

---

## Understanding the Scripts

Want to see what each script does in detail? Read `scripts/README.md` in the repository. Key scripts:

- **`prepare-cluster.sh`** — Cluster setup, AKS creation, Dapr/Radius installation, workspace initialization
- **`bootstrap.sh`** — Recipe publishing, environment deployment, app deployment, component backfill, validation
- **`publish-radius-recipes.sh`** — Publishes custom Radius recipes to an OCI registry
- **`apply-dapr-components-from-recipes.sh`** — Projects Dapr component manifests from deployed Radius recipe metadata (recommended manual fallback)
- **`validate-deployment.sh`** — End-to-end smoke tests (state, workflows, pub/sub)

---

## CI/CD Alternative Path

**Using GitHub Actions instead of local scripts?**

The repository includes `.github/workflows/deploy-azure.yml` which automates the same deployment pipeline. Configure it with the **service principal credentials** the workflow currently registers with Radius:

1. **Set up Azure credentials** in GitHub Secrets:
   - `AZURE_CLIENT_ID` — Azure service principal client ID
   - `AZURE_CLIENT_SECRET` — Azure service principal client secret
   - `AZURE_TENANT_ID` — Azure Entra tenant ID
   - `AZURE_SUBSCRIPTION_ID` — Azure subscription ID
   - `RADIUS_KUBECONFIG` — Kubeconfig for the Kubernetes cluster (optional)

2. **Set deployment variables** in GitHub Variables:
   - `AZURE_LOCATION` (e.g., `belgiumcentral`)
   - `AZURE_RESOURCE_GROUP` (e.g., `radiusclaim-rg`)
   - `RADIUS_KUBERNETES_CONTEXT` (optional, uses current context if not set)
   - `RADIUS_KUBERNETES_NAMESPACE` (optional, defaults to `radiusclaim-azure`)

3. **Push to main** or trigger the workflow manually.

GitHub Actions handles the same steps as the scripts: recipe publishing, environment deployment, app deployment, and component projection via `apply-dapr-components-from-recipes.sh`, while using service principal credentials for Radius Azure registration.

---

## Opening the Web UI

Whether you deployed via scripts or GitHub Actions, the result is the same: RadiusClaim is running and accessible.

After `bootstrap.sh` completes successfully, it prints the public URL to the console:

```
RadiusClaim is deployed! Visit:
https://expense-api.<cluster-ip>.nip.io/app
```

Or, if you don't have public ingress configured, use port-forward:

```bash
kubectl port-forward -n radiusclaim-azure-radiusclaim svc/expense-api 8080:8080 &
# Then visit: http://127.0.0.1:8080/app
```

---

## Manual Walkthrough (Deep Dive)

> **ℹ️ This section is optional.** If you've successfully run the scripts above, you don't need this. This walkthrough is a reference for understanding the deployment steps in detail, troubleshooting, or customizing the deployment. Skip to [Troubleshooting](#troubleshooting) if you hit an issue.

---

## Step 1: Azure Login and Subscription Selection

```bash
# Log in to Azure
az login

# List available subscriptions
az account list --query '[].{name:name, id:id, isDefault:isDefault}' -o table

# Select the subscription you want to use
az account set --subscription <YOUR_SUBSCRIPTION_ID_OR_NAME>

# Verify selection
az account show --query '{subscription:name, id:id, tenant:tenantId}' -o table
```

**What this does:**  
Authenticates you with Azure and ensures subsequent commands use the correct subscription. Store your subscription ID for later steps.

---

## Step 2: Create an Azure Resource Group

RadiusClaim's backing services (PostgreSQL, Service Bus, Key Vault) live in a resource group.

```bash
# Set variables for easy reference
export AZURE_RESOURCE_GROUP="radiusclaim-rg"
export AZURE_LOCATION="belgiumcentral"  # or your preferred region

# Create the resource group
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION"

# Verify creation
az group show --name "$AZURE_RESOURCE_GROUP" --query '{name:name, location:location, id:id}' -o table
```

**What this does:**  
Creates a logical container in Azure that will hold the backing services (PostgreSQL, Service Bus, Key Vault) that Radius recipes provision. This is independent of the Kubernetes cluster itself.

---

## Step 3: Provision a Kubernetes Cluster (if needed)

If you already have a Kubernetes cluster with Dapr and Radius, skip to **Step 4**.

> **Fast path:** `./scripts/prepare-cluster.sh --resource-group "$AZURE_RESOURCE_GROUP" --aks-cluster-name radiusclaim-aks --create-aks --install-dapr --install-radius --yes` covers the cluster-prep work in Steps 3–5 and the Radius workspace/group setup in Step 7.

### Option A: Create an AKS Cluster

```bash
# Set cluster variables
export AKS_CLUSTER_NAME="radiusclaim-aks"

# Create the AKS cluster (this takes 5–10 minutes)
az aks create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --node-count 2 \
  --load-balancer-sku standard \
  --enable-managed-identity \
  --network-plugin azure \
  --network-policy azure \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3

# Get credentials to connect kubectl
az aks get-credentials \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing

# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes
```

**What this does:**  
Creates an AKS cluster in Azure with 2–3 nodes, auto-scaling enabled, and Azure networking. This is the **compute surface** where RadiusClaim's services and Dapr components run. The cluster itself is separate from the backing services created in Step 2.

### Option B: Use an Existing Cluster

If you have an on-prem or other Kubernetes cluster, ensure:
1. kubectl can reach it: `kubectl cluster-info`
2. You have write permissions: `kubectl get nodes`

---

## Step 4: Install Dapr on the Kubernetes Cluster

Dapr provides the building blocks (state, pub/sub, service invocation, workflows) that RadiusClaim uses.

```bash
# Install Dapr on your cluster (you need Helm)
# https://dapr.io/

# Quick install (recommended)
curl -sL https://raw.githubusercontent.com/dapr/cli/master/install/install.sh | /bin/bash

# Then install Dapr on the cluster
dapr init -k
# This may take a few minutes

# Verify Dapr is running
kubectl get pods -n dapr-system
# Expected: dapr-sidecar-injector, dapr-placement-server, dapr-sentry, etc. in Running state
```

**What this does:**  
Installs the Dapr control plane into the `dapr-system` namespace. When RadiusClaim services start, Dapr will inject sidecars that handle state, pub/sub, and service invocation.

---

## Step 5: Install Radius Control Plane on the Kubernetes Cluster

Radius orchestrates the deployment of services and wires Dapr components to backing services.

```bash
# Download and install Radius
# https://docs.radapp.io/guides/deploy/deploy-to-kubernetes/

# Quick install
wget -q https://raw.githubusercontent.com/radius-project/radius/main/deploy/install.sh -O - | /bin/bash

# Install Radius on the cluster
rad install kubernetes --set clusterType=generic
# This may take a few minutes

# Verify Radius is running
kubectl get pods -n radius-system
# Expected: controller, dashboard (if enabled), etc. in Running state

# Verify rad CLI recognizes the cluster
rad workspace list
```

**What this does:**  
Installs the Radius control plane into the `radius-system` namespace. When you run `rad deploy`, Radius reads your Bicep files and creates Kubernetes manifests, Dapr components, and Azure resources.

---

## Step 6: Publish Radius Recipe Artifacts

RadiusClaim's Radius recipes (state store, pub/sub, secrets) must be published to a container registry before deployment.

### Create a GitHub Personal Access Token (PAT)

If you're using GitHub Container Registry (GHCR) to publish recipes, you need a personal access token with minimal required permissions.

**Create a fine-grained PAT (Recommended):**

1. Go to [GitHub Settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta)
2. Click **Generate new token**
3. **Token name:** `radiusclaim-ghcr` (or similar)
4. **Expiration:** Choose an expiration (30 days recommended for security; adjust as needed)
5. **Resource owner:** Select your GitHub username or organization
6. **Repository access:** Select *Only select repositories* → choose *RadiusClaim* (or allow all if you prefer)
7. **Permissions:** Under *Packages*, grant:
   - `write:packages` — to push recipe images to GHCR
   - `read:packages` — to read packages if needed
8. Click **Generate token** and **copy it immediately**

**Store the token safely:**

```bash
# Export to environment variables (do NOT commit to version control)
export GITHUB_USERNAME="your-github-username"
export GHCR_TOKEN="ghp_your_token_here"

# Option 1: Let publish script authenticate automatically
# (The script will detect GHCR_TOKEN and GITHUB_USERNAME and perform docker login)

# Option 2: Authenticate manually first, then run the script
echo "$GHCR_TOKEN" | docker login ghcr.io --username "$GITHUB_USERNAME" --password-stdin
```

⚠️ **Security:**
- Never commit tokens to Git or share in Slack/email
- If you accidentally commit a token, GitHub will revoke it automatically
- Rotate tokens periodically (every 30–90 days)
- Tokens are personal—do not share with team members; each person should create their own

---

### If Using GitHub Container Registry (GHCR)

```bash
# Set authentication credentials
# Use the PAT created in the "Create a GitHub Personal Access Token" section above
export GITHUB_USERNAME="your-github-username"
export GHCR_TOKEN="ghp_xxxxxxxxxxxx"  # Your personal access token

# Option 1: The publish script will use GHCR_TOKEN/GITHUB_USERNAME automatically
# Clone or navigate to the RadiusClaim repository
cd /path/to/RadiusClaim

# Publish the recipes (script auto-authenticates with GHCR_TOKEN)
export RECIPE_REGISTRY="ghcr.io/$GITHUB_USERNAME/radiusclaim/recipes"
export RECIPE_TAG="latest"

./scripts/publish-radius-recipes.sh "$RECIPE_REGISTRY" "$RECIPE_TAG"

# Option 2: Pre-authenticate with docker login, then publish
echo "$GHCR_TOKEN" | docker login ghcr.io --username "$GITHUB_USERNAME" --password-stdin
./scripts/publish-radius-recipes.sh "$RECIPE_REGISTRY" "$RECIPE_TAG"

# Verify publication (you should see recipe images in GHCR)
# https://github.com/$GITHUB_USERNAME?tab=packages
```

### Multi-platform Builds (Mac ARM, Linux x86, Windows)

If your local development machine has a different CPU architecture than your Kubernetes cluster (e.g., building on Mac ARM and pushing to an x86 AKS cluster), use `docker buildx` to build for a specific target platform:

```bash
# Check your local architecture
docker info | grep Architecture

# Build for a specific platform (e.g., linux/amd64 for x86 AKS, linux/arm64 for ARM-based clusters)
docker buildx build \
  --file src/expense-api/Dockerfile \
  --platform linux/amd64 \
  --tag "$GHCR_PREFIX/expense-api:$IMAGE_TAG" \
  --push .

docker buildx build \
  --file src/workflow-engine/Dockerfile \
  --platform linux/amd64 \
  --tag "$GHCR_PREFIX/workflow-engine:$IMAGE_TAG" \
  --push .

docker buildx build \
  --file src/notification-svc/Dockerfile \
  --platform linux/amd64 \
  --tag "$GHCR_PREFIX/notification-svc:$IMAGE_TAG" \
  --push .
```

For **multi-platform manifests** (supporting both ARM and x86 in the same image tag), use:

```bash
docker buildx build \
  --file src/expense-api/Dockerfile \
  --platform linux/amd64,linux/arm64 \
  --tag "$GHCR_PREFIX/expense-api:$IMAGE_TAG" \
  --push .
```

⚠️ **Note:** Multi-platform builds require pushing to a registry (`--push`). For local testing, build native only or use `--load` (single platform) with a local builder.

### If Using Local Docker Registry (for testing only)

```bash
# For local testing with a local registry, consult Radius documentation on local recipe development.
# This is advanced; skip this unless you're modifying recipes.
```

**What this does:**  
Packages the three custom Radius recipes (Azure PostgreSQL state store, Azure Service Bus pub/sub, Azure Key Vault secrets) as OCI artifacts in GHCR. The Radius environment definition references these URLs, so they must exist before `rad deploy` runs.

⚠️ **Critical:** Radius downloads recipe artifacts during the `rad deploy` step, independent of Kubernetes image pulls. If a recipe artifact is private and lacks OCI authentication in Radius's credential config, the deployment fails with a 401 error at recipe-download time — **this is NOT fixed by Kubernetes imagePullSecrets**, which only apply to app container image pulls. The current recommended approach is to **make recipe artifacts public**. (For private recipes, Radius requires explicit OCI auth configuration in the Radius credential store, which is beyond the scope of this guide.)

### ⚠️ Important: Package Visibility in GHCR

Package visibility in GitHub Container Registry depends on your publish settings and linked repository. Before you deploy RadiusClaim, verify and configure package visibility. The recommended approach for first-time deployment is to make packages public:

**Option 1: Make All Packages Public (recommended for first deployment)**

Make public all four package groups in GHCR:
1. `radiusclaim/recipes` — **Make this public.** Radius downloads recipes during `rad deploy`.
2. `radiusclaim/expense-api` — **Make this public.** Kubernetes pulls this from the workload namespace.
3. `radiusclaim/workflow-engine` — **Make this public.** Kubernetes pulls this from the workload namespace.
4. `radiusclaim/notification-svc` — **Make this public.** Kubernetes pulls this from the workload namespace.

To make a package public:
1. Go to your GitHub profile → **Packages** tab
2. For each package:
   - Click the package → **Package settings** → scroll to **Danger zone**
   - Select **Make public**

This allows Radius to download recipes and Kubernetes to pull application images without authentication. **This is the current supported happy path.**

**Option 2: Configure an Image Pull Secret for Private Packages (advanced)**

If you keep packages private, you can add a Kubernetes imagePullSecret in the workload namespace to allow Kubernetes to pull app images. However, **this does NOT help with recipe artifacts**. Recipe artifacts must be public or require explicit Radius OCI auth (not covered in this guide).

**For first-time deployments, we strongly recommend Option 1** (make all packages public). This is the tested, working path. Skip ahead to Step 7.

---

## Step 7: Initialize Radius Workspace and Group (Manual Deployment)

If you're deploying via GitHub Actions, skip to **Step 8**. If deploying locally with `rad` CLI:

```bash
# Get your kubeconfig path
export KUBECONFIG="$HOME/.kube/config"

# Create a Radius workspace for your cluster
rad workspace create kubernetes radiusclaim-workspace

# Switch to that workspace
rad workspace switch radiusclaim-workspace

# Create a Radius group (logical grouping of environments/apps)
rad group create radiusclaim-group -w radiusclaim-workspace

# Switch to that group
rad group switch radiusclaim-group -w radiusclaim-workspace

# Verify
rad workspace list
rad group list
```

**What this does:**  
Initializes Radius metadata on your cluster. A workspace represents a Kubernetes cluster; a group is a logical unit within that workspace. This is only needed for local `rad deploy` commands.

---

## Step 8: Deploy the Radius Environment

The environment definition wires Dapr components to Azure backing services.

### Option A: Via GitHub Actions (Recommended)

1. **Configure GitHub Secrets & Variables:**

   Go to your repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret/variable**.

   **Required Secrets:**
    - `AZURE_SUBSCRIPTION_ID` — Your Azure subscription ID
    - `AZURE_CLIENT_ID` — Azure service principal client ID for Radius credential registration
    - `AZURE_CLIENT_SECRET` — Azure service principal client secret for Radius credential registration
    - `AZURE_TENANT_ID` — Azure tenant ID for Radius credential registration
    - `RADIUS_KUBECONFIG` — Your kubeconfig file content (base64 or raw)

   **Required Variables:**
   - `AZURE_LOCATION` — Azure region (e.g., `belgiumcentral`)
   - `AZURE_RESOURCE_GROUP` — Resource group name (e.g., `radiusclaim-rg`)

   **Optional Variables:**
   - `RADIUS_KUBERNETES_CONTEXT` — kubectl context name (if not using current context)
    - `RADIUS_KUBERNETES_NAMESPACE` — Kubernetes namespace where Radius deploys the environment (optional; if not set, defaults to current cluster context)

2. **Create a Service Principal for the Workflow (one-time):**

   Scope it to the target resource group so the workflow has least-privilege access for the Azure backing services it provisions.

   ```bash
   export AZURE_RESOURCE_GROUP="radiusclaim-rg"
   export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

   az ad sp create-for-rbac \
     --name "radiusclaim-github-actions" \
     --role Contributor \
     --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP" \
     --query '{clientId:appId,clientSecret:password,tenantId:tenant}' \
     -o jsonc
   ```

   Copy the returned values into these GitHub secrets:
   - `AZURE_CLIENT_ID` ← `clientId`
   - `AZURE_CLIENT_SECRET` ← `clientSecret`
   - `AZURE_TENANT_ID` ← `tenantId`
   - `AZURE_SUBSCRIPTION_ID` ← your Azure subscription ID

3. **Trigger the Workflow:**

   ```bash
   # Push code to main branch OR manually trigger via GitHub UI
   git push origin main
   
   # Or go to Actions → deploy-azure → Run workflow
   ```

   The workflow will:
   - Build and push service images to GHCR
   - Publish Radius recipes to GHCR
   - Deploy the Radius environment (`azure-radius.bicep`)
   - Deploy the application model (`app.bicep`)
   - Validate the deployment

4. **Check the Workflow Output:**

   The workflow logs will show:
   ```
   Radius environment deployed to namespace: radiusclaim-azure
   Workload namespace: radiusclaim-azure-radiusclaim
   ```

   Use the workload namespace for validation, logs, and `kubectl port-forward`.

### Option B: Manual Deployment with `rad` CLI

If you prefer the scripted operator path, run `./scripts/prepare-cluster.sh` once for cluster readiness, then use `./scripts/bootstrap.sh --resource-group "$AZURE_RESOURCE_GROUP"` for the repeatable deployment layer. The commands that follow remain the detailed, step-by-step reference.

```bash
# Set environment variables
export GITHUB_USERNAME="your-github-username"
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_CLIENT_ID="<azure-service-principal-client-id>"
export AZURE_CLIENT_SECRET="<azure-service-principal-client-secret>"
export AZURE_RESOURCE_GROUP="radiusclaim-rg"
export AZURE_LOCATION="belgiumcentral"
export AZURE_TENANT_ID="<azure-tenant-id>"
# Principal object ID for RBAC assignments — auto-resolves from service principal if not set.
# For user identity mode: export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
# For managed identity: export AZURE_PRINCIPAL_ID=<managed-identity-object-id>
export AZURE_PRINCIPAL_ID="${AZURE_PRINCIPAL_ID:-$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)}"
export AZURE_PROVIDER_SCOPE="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP"
export RADIUS_ENVIRONMENT_NAME="azure"
# The Kubernetes namespace is explicitly configured in azure-radius.bicep as "radiusclaim-azure".
# This is the environment namespace where Radius deploys infrastructure resources.
# Application workloads are deployed to a separate workload namespace (radiusclaim-azure-radiusclaim).
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure"
export RECIPE_REGISTRY="ghcr.io/$GITHUB_USERNAME/radiusclaim/recipes"
export RECIPE_TAG="latest"

# Create or switch to the target environment (idempotent)
rad env create "$RADIUS_ENVIRONMENT_NAME" || true
rad env switch "$RADIUS_ENVIRONMENT_NAME"

# Register Azure provider credentials with the Radius control plane
# This enables Radius to authenticate with Azure when provisioning backing services (PostgreSQL, Service Bus, Key Vault, etc.)
rad credential register azure sp \
  --client-id "$AZURE_CLIENT_ID" \
  --client-secret "$AZURE_CLIENT_SECRET" \
  --tenant-id "$AZURE_TENANT_ID"

# Verify the credential was registered
rad credential list
# Expected: Shows azure provider in the list

# If your Radius installation is configured for workload identity instead,
# use: rad credential register azure wi --client-id "$AZURE_CLIENT_ID" --tenant-id "$AZURE_TENANT_ID"

# Deploy the Azure-backed Radius environment
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters environmentName="$RADIUS_ENVIRONMENT_NAME" \
  --parameters kubernetesNamespace="$RADIUS_KUBERNETES_NAMESPACE" \
  --parameters azureProviderScope="$AZURE_PROVIDER_SCOPE" \
  --parameters azureSubscriptionId="$AZURE_SUBSCRIPTION_ID" \
  --parameters azureResourceGroupName="$AZURE_RESOURCE_GROUP" \
  --parameters location="$AZURE_LOCATION" \
  --parameters daprAzureClientId="$AZURE_CLIENT_ID" \
  --parameters daprAzurePrincipalId="$AZURE_PRINCIPAL_ID" \
  --parameters daprAzurePrincipalName="$MANAGED_IDENTITY_NAME" \
  --parameters azureTenantId="$AZURE_TENANT_ID" \
  --parameters recipeRegistry="$RECIPE_REGISTRY" \
  --parameters recipeTag="$RECIPE_TAG"

# Verify the environment
rad env list
```

**What this does:**  
Deploys the Radius environment to your Kubernetes cluster. This creates:
- A Kubernetes namespace: **`radiusclaim-azure`** (the *environment* namespace, as defined in `azure-radius.bicep`)
  - This is a logical container for the Radius environment and backing service definitions.
  - **Do NOT create imagePullSecrets here** — the recipes themselves don't pull container images.
- A separate *workload* namespace for deployed applications: **`radiusclaim-azure-radiusclaim`** (created when you deploy the RadiusClaim app in Step 9)
  - This is where your three services (expense-api, workflow-engine, notification-svc) actually run.
  - If you need private GHCR package access, imagePullSecrets go in the *workload* namespace.
- Azure resource groups and backing services (PostgreSQL, Service Bus, Key Vault) via Radius recipes
- A statestore recipe that provisions Azure PostgreSQL with Entra RBAC (role-based access control) and transactional state for Dapr Actors. Components use workload identity — no shared keys or connection strings.
- Radius `Applications.Dapr/*` resources that *describe* the Dapr components (state store, pub/sub, secrets)

> **⚠️ Component projection gap:** Radius may report the `Applications.Dapr/*` resources as `Succeeded` even though no Kubernetes `components.dapr.io` CRDs were actually projected into the cluster. After deploying the application in Step 9, you **must** verify that Dapr Component objects exist in the workload namespace. If they are missing, run the backfill step in **Step 9a**.

### (Optional) Step 8a: Understanding Namespace Roles

Before Step 8b, understand the difference between the two namespaces:

- **Environment namespace** (`radiusclaim-azure`): Created by `rad deploy infra/radius/environments/azure-radius.bicep`. Holds the Radius environment definition and backing-service specs. Does NOT run application workloads or Dapr sidecars.
- **Workload namespace** (`radiusclaim-azure-radiusclaim`): Created automatically when you deploy the RadiusClaim app in Step 9. Holds the three running services (expense-api, workflow-engine, notification-svc) and their Dapr sidecars.

**imagePullSecrets belong in the workload namespace** (Step 8b, if needed). The environment namespace does not pull container images, so it doesn't need a pull secret.

### (Optional) Step 8b: Configure Image Pull Secret for Private GHCR Packages

**This step is optional.** If you made your GHCR recipe and app packages public (Option 1 in Step 6), you can skip to Step 9.

If you chose **Option 2** (private GHCR packages), you must configure the pull secret **in the workload namespace after deploying the app in Step 9**, not before. For now, proceed to Step 9 and return to this step afterward.

**To be completed after Step 9:**

```bash
# After deploying the app, the workload namespace exists: radiusclaim-azure-radiusclaim
# Kubernetes automatically creates this namespace when the app deploys

export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
export GITHUB_USERNAME="your-github-username"
export GHCR_TOKEN="ghp_xxxxxxxxxxxx"  # Your personal access token

# Confirm which service accounts the deployments actually use before patching.
# RadiusClaim pods use named service accounts, not 'default'.
kubectl get deploy -n "$WORKLOAD_NAMESPACE" \
  -o custom-columns='NAME:.metadata.name,SA:.spec.template.spec.serviceAccountName'
# Expected output:
# NAME               SA
# expense-api        expense-api
# workflow-engine    workflow-engine
# notification-svc   notification-svc

# Create the pull secret in the WORKLOAD namespace
# (The env namespace radiusclaim-azure does not run app containers; the secret goes here.)
kubectl create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USERNAME" \
  --docker-password="$GHCR_TOKEN" \
  --namespace "$WORKLOAD_NAMESPACE"

# Patch each named service account to include the pull secret.
# RadiusClaim deployments use named service accounts (not 'default'),
# so patching 'default' alone has no effect on these pods.
for SA in expense-api workflow-engine notification-svc; do
  kubectl patch serviceaccount "$SA" \
    --namespace "$WORKLOAD_NAMESPACE" \
    --type merge \
    -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
done

# Verify the secret exists and each service account references it
kubectl get secrets -n "$WORKLOAD_NAMESPACE" | grep ghcr-pull
for SA in expense-api workflow-engine notification-svc; do
  echo -n "$SA imagePullSecrets: "
  kubectl get serviceaccount "$SA" -n "$WORKLOAD_NAMESPACE" \
    -o jsonpath='{.imagePullSecrets[*].name}' && echo
done
```

This allows Kubernetes to pull your application images from a private GHCR repository.

> **Why named service accounts?** Radius creates a dedicated service account for each `Applications.Core/containers` resource it deploys. Pods inherit `imagePullSecrets` from the service account named in `spec.serviceAccountName`, so patching only `default` leaves the named accounts — and therefore the pods — without pull credentials.

---

## Step 9: Deploy the RadiusClaim Application

The application model defines the three services and their connections to Dapr components.

### Via GitHub Actions

The workflow automatically deploys the app after the environment is ready.

### Via `rad` CLI (Manual)

```bash
# Build and push container images to GHCR
export GITHUB_USERNAME="your-github-username"
export GHCR_PREFIX="ghcr.io/$GITHUB_USERNAME/radiusclaim"
export IMAGE_TAG="v1.0"  # or use git SHA, e.g., ${GIT_SHA::7}

# Log in to GHCR
docker login ghcr.io --username "$GITHUB_USERNAME"

# Build and push images
# Note: Use native Docker build (below) if your local machine matches your Kubernetes cluster architecture.
# If deploying to a different architecture (e.g., building on Mac ARM and deploying to x86 AKS),
# use docker buildx (see "Multi-platform builds" section).

docker build --file src/expense-api/Dockerfile --tag "$GHCR_PREFIX/expense-api:$IMAGE_TAG" .
docker push "$GHCR_PREFIX/expense-api:$IMAGE_TAG"

docker build --file src/workflow-engine/Dockerfile --tag "$GHCR_PREFIX/workflow-engine:$IMAGE_TAG" .
docker push "$GHCR_PREFIX/workflow-engine:$IMAGE_TAG"

docker build --file src/notification-svc/Dockerfile --tag "$GHCR_PREFIX/notification-svc:$IMAGE_TAG" .
docker push "$GHCR_PREFIX/notification-svc:$IMAGE_TAG"

# Deploy the application with the published images
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry="$GHCR_PREFIX" \
  --parameters imageTag="$IMAGE_TAG" \
  --parameters deploymentTarget='radius'

# Wait for deployments to stabilize
# Set your workload namespace (where app pods actually run, NOT the environment namespace)
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
kubectl rollout status deployment/expense-api -n "$WORKLOAD_NAMESPACE" --timeout=5m
kubectl rollout status deployment/workflow-engine -n "$WORKLOAD_NAMESPACE" --timeout=5m
kubectl rollout status deployment/notification-svc -n "$WORKLOAD_NAMESPACE" --timeout=5m
```

**What this does:**  
Deploys the three RadiusClaim services (expense-api, workflow-engine, notification-svc) to the Kubernetes cluster with Dapr sidecars injected. The Radius app model wires them to the Dapr components created in Step 8.

> **⚠️ Critical Prerequisite:** Before running this step, verify that **Step 8 succeeded** and the Radius environment was created:
> ```bash
> rad env show azure
> # Expected: Shows compute kind as kubernetes, namespace, and Azure provider scope
> ```
> Dapr Component CRDs may **not** exist yet — that is expected. Radius reports `Applications.Dapr/*` resources as Succeeded even when no Kubernetes `components.dapr.io` objects were projected. After this step completes, **Step 9a** verifies and backfills the components.

---

## Step 9a: Verify Dapr Components (bootstrap) / Apply Components (manual path)

> **Bootstrap path:** `bootstrap.sh` automatically runs `apply-dapr-components-from-recipes.sh` after app deployment. If you used `bootstrap.sh` and it completed successfully, your components are already present — skip to Step 10.
>
> This step is only needed if:
> - You deployed manually via `rad deploy` (the steps above, without `bootstrap.sh`)
> - `bootstrap.sh` was interrupted or failed at the component creation phase
> - You want to verify components are present after a troubleshooting restart

After a Radius app deployment, Dapr sidecars need `components.dapr.io` CRDs in the **workload** namespace. Radius may report `Applications.Dapr/*` resources as Succeeded without projecting these objects — this is a known component projection behaviour that `bootstrap.sh` compensates for automatically.

### Check for existing components

```bash
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"

kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets
#
# If you see all three components listed, skip to Step 10.
# If the command returns "No resources found", continue below.
```

### Confirm the gap (optional diagnostic)

```bash
# Radius reports success...
rad resource list -a radiusclaim
# Expected: Applications.Dapr/* resources show Succeeded

# ...but Kubernetes has no component CRDs anywhere
kubectl get components.dapr.io -A
# If empty: the projection gap is confirmed

# Sidecar logs confirm the runtime impact
kubectl logs -n "$WORKLOAD_NAMESPACE" deployment/expense-api -c daprd --tail=20 2>/dev/null | grep -i "component"
# Expected (broken): Only loads kubernetes secretstore, never loads statestore/pubsub
```

### Apply Dapr components (manual path or bootstrap fallback)

```bash
./scripts/apply-dapr-components-from-recipes.sh \
  --environment "$RAD_ENV" \
  --application "$RAD_APP" \
  --namespace "$WORKLOAD_NAMESPACE" \
  --tenant-id "$AZURE_TENANT_ID" \
  --client-id "$AZURE_CLIENT_ID"
```

The script:
1. Queries Radius for the deployed `Applications.Dapr/*` resources
2. Parses Azure resource IDs from `status.outputResources[]` (Storage Account, Service Bus namespace, Key Vault vault name)
3. Creates Kubernetes `components.dapr.io` manifests using workload identity (no client secrets)
4. Applies `statestore`, `pubsub`, and `platform-secrets` components to the workload namespace

> **Workload Identity Model:** All Dapr components authenticate via OIDC federated credentials — **no client secrets, connection strings, or shared keys** are stored in Kubernetes secrets or the cluster.

### Verify the backfill

```bash
# Components should now exist
kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets

# Restart pods so sidecars pick up the new components
kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc \
  -n "$WORKLOAD_NAMESPACE"

kubectl rollout status deployment/expense-api -n "$WORKLOAD_NAMESPACE" --timeout=5m

# Confirm sidecar loads the components
kubectl logs -n "$WORKLOAD_NAMESPACE" deployment/expense-api -c daprd --tail=20 | grep "Component loaded"
# Expected: Lines showing statestore, pubsub loaded
```

**What this does:**  
Bridges the gap between Radius's logical Dapr resource model and the Kubernetes runtime. Without this step, services start with Dapr sidecars that cannot find `statestore` or `pubsub`, causing all expense operations to fail.

---

## Step 10: Verify Deployment and Get the Public Endpoint

```bash
# Set your workload namespace (where app pods actually run, NOT the environment namespace)
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"

# Check that all services are running
kubectl get deployments -n "$WORKLOAD_NAMESPACE"
# Expected: 3 deployments in Running state

kubectl get pods -n "$WORKLOAD_NAMESPACE"
# Expected: 3+ pods (one per service)

# Choose an access path for expense-api.
# If your platform prints or provisions an HTTP endpoint, you can use that URL.
# The deterministic path for this repo is a workload-namespace port-forward:
kubectl port-forward -n "$WORKLOAD_NAMESPACE" svc/expense-api 8080:8080 &
echo "Expense API (port-forward): http://127.0.0.1:8080"

export EXPENSE_API_URL="http://127.0.0.1:8080"
```

**What this does:**  
Confirms that all services are running and provides a reliable access path for the hosted UI and API.

---

## Step 11: Open the Web UI in a Browser

RadiusClaim includes a lightweight web UI for submitting expenses and viewing history.

```bash
# Open the app in your default browser
# Use the endpoint from Step 10

open "$EXPENSE_API_URL/app"        # EXPENSE_API_URL already includes the scheme (http://)
# or
open "http://127.0.0.1:8080/app"  # if using port-forward
```

**What you'll see:**
- A form to submit an expense (amount, description, employee ID)
- Recent expense history with status (Submitted, Approved, Rejected)
- Workflow correlation IDs and telemetry information
- Live updates as the workflow processes expenses

> **Reality check:** loading `/app` only proves the shell is reachable. It does **not** prove the full local submission path is ready. Plain `dotnet run --project src/expense-api/ExpenseApi.csproj` starts the ASP.NET app, but real `/expenses` reads and submissions still fail until `expense-api` runs with a Dapr sidecar and the local `statestore` component. Workflow telemetry has one extra dependency: `workflow-engine` must also be reachable through Dapr.

If you're reproducing the same flow locally, use the Dapr-backed startup path:

```bash
docker compose -f infra/dapr/local/docker-compose.yaml up -d

# Match --app-port to the current launch profile in src/workflow-engine/Properties/launchSettings.json
dapr run --app-id workflow-engine --app-port 5299 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/workflow-engine/WorkflowEngine.csproj

dapr run --app-id expense-api --app-port 5062 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/expense-api/ExpenseApi.csproj
```

After both services are running, open `http://localhost:5062/app`.

---

## Step 12: Validate the Deployment

Use the included validation script to confirm the full flow works:

```bash
# Run the validation script
./scripts/validate-deployment.sh "$EXPENSE_API_URL"
# or
./scripts/validate-deployment.sh "http://127.0.0.1:8080"  # if using port-forward

# Expected output:
# ✅ Health check passed
# ✅ $50 auto-approve flow passed
# ✅ $150 manual-review flow passed
# ✅ $100.00 boundary case passed
```

This validates:
- API health endpoint
- Auto-approve flow (expenses < $100)
- Manual-review flow (expenses ≥ $100)
- Dapr state persistence
- Workflow orchestration
- Service-to-service invocation

---

## Troubleshooting

### Kubernetes Cluster Not Reachable

**Symptom:** `kubectl cluster-info` fails or shows "connection refused"

**Solution:**
```bash
# Ensure kubeconfig is set
export KUBECONFIG="$HOME/.kube/config"

# Re-authenticate with AKS
az aks get-credentials --resource-group "$AZURE_RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing

# Check the current context
kubectl config current-context
kubectl config get-contexts
```

### Dapr or Radius Control Plane Not Running

**Symptom:** `kubectl get pods -n dapr-system` or `-n radius-system` shows failed or pending pods

**Solution:**
```bash
# Check pod status and logs
kubectl logs -n dapr-system -l app=dapr-sidecar-injector --tail=50
kubectl logs -n radius-system -l app.kubernetes.io/name=controller --tail=50

# Restart the control planes if needed
kubectl rollout restart deployment/dapr-sidecar-injector -n dapr-system
kubectl rollout restart deployment/controller -n radius-system
```

### Troubleshooting GHCR Auth

**What is GHCR and why does RadiusClaim use it?**

GHCR (GitHub Container Registry) is GitHub's hosted container registry. RadiusClaim uses GHCR to store:
- **Radius recipe artifacts** — The three custom recipes (state store, pub/sub, secrets) packaged as OCI images
- **Application container images** — The three RadiusClaim services (expense-api, workflow-engine, notification-svc)

Recipes must be published to a registry before `rad deploy` can reference them. The default setup uses GHCR because it's free, integrated with GitHub, and convenient for teams.

---

**Bootstrap Error: "Recipe publishing to ghcr.io is required but GHCR credentials are missing"**

**When you see this:**
```
ERROR: Recipe publishing to ghcr.io is required but GHCR credentials are missing.

Bootstrap detected that Radius recipe artifacts need to be published to:
  ghcr.io/your-username/radiusclaim/recipes

However, GHCR_TOKEN and/or GHCR_USERNAME environment variables are not set.

To fix this, you need to:
  1. Create a GitHub Personal Access Token (PAT) with 'write:packages' scope:
     → Visit https://github.com/settings/tokens/new
     → Select 'write:packages' scope (read:packages is also selected automatically)
     → Generate the token and copy it
  
  2. Export the credentials in your shell:
     export GHCR_USERNAME=<your-github-username>
     export GHCR_TOKEN=<your-personal-access-token>
  
  3. Re-run bootstrap

Alternatively, authenticate with the GitHub CLI to auto-populate credentials:
  gh auth login
```

**What it means:** Bootstrap detected that Radius recipes need to be published (because they're not already in the registry or your local recipe source has changes), but it can't authenticate to GHCR without credentials. This is a hard stop — bootstrap cannot proceed without them.

**What triggers this error:**
- Running bootstrap with a `RECIPE_REGISTRY` pointing to GHCR (`ghcr.io/...`)
- Recipe artifacts don't exist in the registry for the requested tag, **OR**
- Your local recipe source files have uncommitted Git changes

**Solutions:**

1. **Option 1: Auto-populate from GitHub CLI (Easiest)**
   ```bash
   # If you have 'gh' CLI installed:
   gh auth login
   # Then run bootstrap — it will auto-detect credentials
   ./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
   ```
   Bootstrap will log: `ℹ Auto-populated GHCR credentials from 'gh' CLI (user: your-username)`

2. **Option 2: Explicitly set GHCR credentials**
   ```bash
   export GITHUB_USERNAME="your-github-username"
   export GHCR_TOKEN="ghp_xxxxxxxxxxxx"  # Your personal access token
   ./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
   ```
   Bootstrap will log: `ℹ GHCR credentials verified: GHCR_USERNAME=your-username`

3. **How to create a GHCR Personal Access Token (PAT):**
   - Go to [GitHub Settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta)
   - Click **Generate new token**
   - **Token name:** `radiusclaim-ghcr`
   - **Expiration:** 30 days (recommended for security)
   - **Resource owner:** Select your GitHub username
   - **Permissions:** Under *Packages*, grant `write:packages` and `read:packages`
   - Click **Generate token** and **copy it immediately** (you can't view it again)
   - Never commit the token to Git or share in chat; each team member should create their own

---

**Recipes Not Published**

**Symptom:** `rad deploy` fails with "recipe not found" or registry errors during the recipe download step

**What happened:** Bootstrap attempted to publish recipes to GHCR but failed due to missing credentials or authentication issues.

**Solution:**
```bash
# Set credentials (if not already set)
export GITHUB_USERNAME="your-github-username"
export GHCR_TOKEN="ghp_xxxxxxxxxxxx"

# Option 1: Use environment variables (publish script auto-authenticates)
./scripts/publish-radius-recipes.sh "$RECIPE_REGISTRY" "$RECIPE_TAG"

# Option 2: Pre-authenticate with docker, then publish
echo "$GHCR_TOKEN" | docker login ghcr.io --username "$GITHUB_USERNAME" --password-stdin
./scripts/publish-radius-recipes.sh "$RECIPE_REGISTRY" "$RECIPE_TAG"

# Verify images exist in GHCR
docker pull "$RECIPE_REGISTRY/state-store:$RECIPE_TAG"

# Re-run bootstrap to deploy the app
./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes
```

**Common errors and fixes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` | PAT is missing, expired, or has insufficient permissions | Create a new PAT with `write:packages` scope; ensure `GHCR_TOKEN` is exported |
| `403 Forbidden` | PAT exists but lacks `write:packages` permission or the token was revoked | Recreate the PAT with correct permissions |
| `unknown: GHCR_TOKEN not set` | Environment variable not exported in current shell | Run `export GHCR_TOKEN="ghp_..."` and retry |
| `docker login` fails silently | Docker daemon not running or GHCR server unreachable | Check `docker ps` and network connectivity; verify GHCR is accessible: `curl https://ghcr.io/v2/` |

---

### Azure Authentication Mode Selection

**Background:** Bootstrap auto-detects whether to use **service principal (sp)** or **workload identity (wi)** based on your environment variables. Understanding which mode is in use helps with troubleshooting credential issues.

**How Bootstrap Chooses Auth Mode:**

1. **Service Principal (sp)** — if you provide:
   - `AZURE_CLIENT_ID` + `AZURE_CLIENT_SECRET` + `AZURE_TENANT_ID`
   - Uses a secret for authentication. Credentials must be rotated securely.
   - No cluster OIDC configuration required.

2. **Workload Identity (wi)** — if you provide:
   - `AZURE_CLIENT_ID` + `AZURE_TENANT_ID` (no `AZURE_CLIENT_SECRET`)
   - Uses federated credentials — no secrets stored in the cluster.
   - Requires OIDC issuer and workload identity addons on the AKS cluster.
   - **Default and recommended mode.** Bootstrap auto-enables cluster addons if missing (takes ~2 minutes).

3. **Reuse Existing** — if the Radius workspace already has credentials registered:
   - No new credential registration; bootstrap skips credential setup.

**To See Which Mode Was Detected:**

Watch for the "Azure Authentication" section in bootstrap output:
```
==> Azure Authentication
ℹ Azure auth mode: Workload Identity (wi)
ℹ   Detected: AZURE_CLIENT_ID and AZURE_TENANT_ID (no AZURE_CLIENT_SECRET)
ℹ   This mode uses federated credentials — no secrets stored in the cluster.
ℹ   Requires OIDC issuer and workload identity addons on the AKS cluster.
ℹ   Bootstrap will auto-enable if not already configured (takes ~2 minutes).
```

**To Force a Specific Mode:**

```bash
# Force service principal mode
./scripts/bootstrap.sh --resource-group <rg> --azure-auth-mode sp

# Force workload identity mode
./scripts/bootstrap.sh --resource-group <rg> --azure-auth-mode wi
```

**Troubleshooting Credential Failures:**

- **"AZURE_CLIENT_ID is required"** — Set `AZURE_CLIENT_ID` in your environment.
- **"AZURE_TENANT_ID is required"** — Set `AZURE_TENANT_ID`.
- **"Could not resolve the Microsoft Entra principal"** — The service principal may not exist in your tenant, or your account lacks permission to query it. See [Resolving Principal ID](#resolving-principal-id) below.
- **Workload identity auto-enable failed** — Check that your Azure CLI credentials have permission to run `az aks update` with `--enable-oidc-issuer` and `--enable-workload-identity` flags.

### `platform-secrets` fails because the Key Vault name is in deleted state

**Symptom:** `rad deploy infra/radius/app.bicep` or `./scripts/bootstrap.sh` reports that the Key Vault name already exists in deleted state

**Solution:**
```bash
# Inspect the deleted vault entry
az keyvault list-deleted --query "[?name=='<vault-name>']"

# If it belongs to the same subscription/resource group/location as this deployment,
# restore it and rerun bootstrap or rad deploy
az keyvault recover --name <vault-name> --location <region>
```

- The scripted bootstrap path already performs this check and restore flow when it is safe to do so.
- If Azure can only recover the vault into some other resource group or location, do **not** force the Radius app deploy to continue. Purge the deleted vault if you own it, wait for scheduled purge, or switch to a different Radius environment name so the deterministic Key Vault name changes.

### Services Not Starting

**Symptom:** Pods are pending or crash-looping (verify with: `kubectl get pods -n <your-namespace>`)

**Solution:**
```bash
# App pods run in the WORKLOAD namespace (radiusclaim-azure-radiusclaim), not the environment namespace.
# Always use the workload namespace for pod inspection:
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"

# Check pod events
kubectl describe pod <pod-name> -n "$WORKLOAD_NAMESPACE"

# Check logs
kubectl logs <pod-name> -n "$WORKLOAD_NAMESPACE"

# Verify images are accessible
docker pull "$GHCR_PREFIX/expense-api:$IMAGE_TAG"

# Check resource quotas
kubectl describe resourcequota -n "$WORKLOAD_NAMESPACE"
```

If you see `401 Unauthorized` or `403 Forbidden` pull errors, the issue is image registry access or authentication:

```bash
# Confirm the two namespaces:
kubectl get namespaces | grep radiusclaim
# radiusclaim-azure              — environment namespace (Radius environment, no app pods)
# radiusclaim-azure-radiusclaim  — workload namespace (expense-api, workflow-engine, notification-svc, Dapr components)

# Pull secrets belong in the WORKLOAD namespace only:
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
export GHCR_TOKEN='<github-pat-with-read:packages>'

# Create the pull secret in the workload namespace
# GHCR_USERNAME is auto-detected from your GitHub login via gh CLI
kubectl create secret docker-registry ghcr-pull \
  --namespace "$WORKLOAD_NAMESPACE" \
  --docker-server=ghcr.io \
  --docker-username="$(gh api user --jq .login)" \
  --docker-password="$GHCR_TOKEN"

# RadiusClaim pods use named service accounts, not 'default'.
# Patch each one individually — patching 'default' alone will not resolve ErrImagePull.
for SA in expense-api workflow-engine notification-svc; do
  kubectl patch serviceaccount "$SA" \
    --namespace "$WORKLOAD_NAMESPACE" \
    --type merge \
    -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
done

# Restart pods so they pick up the updated pull credentials
kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc \
  -n "$WORKLOAD_NAMESPACE"
```

If the failing container is **`daprd`** rather than the app container, switch to sidecar-focused checks:

```bash
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
POD=$(kubectl get pods -n "$WORKLOAD_NAMESPACE" --no-headers | awk '/expense-api/ {print $1; exit}')

kubectl logs -n "$WORKLOAD_NAMESPACE" "$POD" -c daprd --previous --tail=120
kubectl get component statestore pubsub -n "$WORKLOAD_NAMESPACE" -o yaml
```

- If the log shows `KeyBasedAuthenticationNotPermitted`, the problem is the **statestore component auth**, not app annotations or env wiring. The component was not properly configured for workload identity. Repair it by rerunning the backfill script:
  ```bash
  export AZURE_PRINCIPAL_ID="${AZURE_PRINCIPAL_ID:-$(az identity show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name radiusclaim-workload-identity \
    --query principalId -o tsv)}"
  
  ./scripts/apply-dapr-components-from-recipes.sh \
    --environment "$RADIUS_ENVIRONMENT_NAME" \
    --application radiusclaim \
    --namespace "$WORKLOAD_NAMESPACE" \
    --tenant-id "$AZURE_TENANT_ID" \
    --client-id "$AZURE_CLIENT_ID"
  
  kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc -n "$WORKLOAD_NAMESPACE"
  ```

- If the pubsub component is in a mixed auth state (both `namespaceName` and `connectionString` present), patch it to the workload identity path:
  ```bash
  kubectl patch component pubsub -n "$WORKLOAD_NAMESPACE" --type merge \
    -p '{"spec":{"metadata":[{"name":"namespaceName","value":"<namespace>.servicebus.windows.net"},{"name":"azureClientId","value":"'"$AZURE_CLIENT_ID"'"},{"name":"disableEntityManagement","value":"true"}]}}'
  kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc -n "$WORKLOAD_NAMESPACE"
  ```

### Namespace Drift During Application Update

**Symptom:** Error when running `rad deploy infra/radius/app.bicep`:
```
Updating an application's Kubernetes namespace from 'radiusclaim-azure-radiusclaim'
to 'radiusclaim-azure-radiusclaim-radiusclaim' requires the application to be deleted and redeployed.
```

**Cause:** Radius has detected a mismatch in the workload namespace. This can occur when re-deploying the application against an environment that already has a previous application deployment in place. Radius computes the workload namespace by appending the application name to the environment's namespace parameter, and when internal state becomes inconsistent, it cannot safely re-reconcile the namespace.

**Recovery:**

1. **Delete the existing Radius application** to clear the stale workload namespace:
   ```bash
   ./rad app delete radiusclaim
   ```

2. **Delete the workload namespace** if Kubernetes resources linger:
   ```bash
   kubectl delete namespace radiusclaim-azure-radiusclaim --ignore-not-found
   ```

3. **Re-deploy the environment and application** from scratch:
   ```bash
   export KUBECONFIG="/path/to/kubeconfig"
   export AZURE_PROVIDER_SCOPE="/subscriptions/<id>/resourceGroups/<rg>"
   export AZURE_LOCATION="<location>"
   
   # Deploy environment
   ./rad deploy infra/radius/environments/azure-radius.bicep \
     --parameters kubernetesNamespace="radiusclaim-azure" \
     --parameters azureProviderScope="$AZURE_PROVIDER_SCOPE" \
     --parameters azureSubscriptionId="$AZURE_SUBSCRIPTION_ID" \
     --parameters azureResourceGroupName="$AZURE_RESOURCE_GROUP" \
     --parameters location="$AZURE_LOCATION"
   
   # Deploy application
   ./rad deploy infra/radius/app.bicep \
     --parameters containerRegistry="$GHCR_PREFIX" \
     --parameters imageTag="$IMAGE_TAG" \
     --parameters deploymentTarget='radius'
   ```

**Why deletion is required:** Radius's idempotency for Kubernetes namespaces cannot self-heal once the mismatch is detected. The application resource must be deleted and recreated with a fresh namespace computation.

**Note:** This is not a configuration error in the repository. The bicep files are correct. The namespace mismatch is a Radius operator reconciliation issue that requires a clean redeploy.

### Image Reference Mismatch

**Symptom:** Pod events reference an unexpected registry path or old tag (e.g., a previous environment's registry)

**Solution:**

This can happen if container images were rebuilt with different parameters. Re-run the deployment with your correct registry and tag:

```bash
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry="$GHCR_PREFIX" \
  --parameters imageTag='<published-tag>' \
  --parameters deploymentTarget='radius'
```

Verify the corrected images are specified:
```bash
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
kubectl describe deployment expense-api -n "$WORKLOAD_NAMESPACE" | grep -i image
```

### Public Endpoint Not Accessible

**Symptom:** You need a reliable URL for the hosted UI or API after deployment.

**Solution:**
```bash
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"

# Use a workload-namespace port-forward for deterministic access
kubectl port-forward -n "$WORKLOAD_NAMESPACE" svc/expense-api 8080:8080 &
# Access via http://127.0.0.1:8080
```

### `/app` Loads, but Local Expense Submission Fails

**Symptom:** The browser renders `/app`, but local loads or submissions fail. The UI typically shows one of these truthful runtime messages:

- `Loading and submitting expenses requires the expense-api Dapr sidecar plus the configured statestore. Workflow telemetry also needs workflow-engine to be reachable through Dapr.`
- `The expense record is available, but workflow telemetry needs workflow-engine to be reachable through Dapr.`

**Solution:**
```bash
docker compose -f infra/dapr/local/docker-compose.yaml up -d

dapr run --app-id workflow-engine --app-port 5299 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/workflow-engine/WorkflowEngine.csproj

dapr run --app-id expense-api --app-port 5062 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/expense-api/ExpenseApi.csproj
```

Do **not** rely on plain `dotnet run` for `expense-api` when validating submission behavior. That only brings up the ASP.NET host; the real write path still needs the Dapr sidecar plus the configured `statestore`. Workflow telemetry stays unavailable until `workflow-engine` is also up through Dapr.

### Validation Script Fails

**Symptom:** `./scripts/validate-deployment.sh` reports failures

**Solution:**
```bash
# Verify the URL is reachable
curl "http://$EXPENSE_API_URL/healthz"

# Check if jq is installed
jq --version
# If not: brew install jq (or apt-get install jq)

# Run with verbose output to see which step fails
bash -x ./scripts/validate-deployment.sh "$EXPENSE_API_URL"
```

### Redeploying After Code Changes

Once you've verified the initial deployment works, you can iterate on the code and redeploy the updated images:

**Rebuild and push images:**
```bash
# Use native Docker build (fastest if your local machine matches cluster architecture)
docker build --file src/expense-api/Dockerfile --tag "$GHCR_PREFIX/expense-api:$NEW_TAG" .
docker push "$GHCR_PREFIX/expense-api:$NEW_TAG"

docker build --file src/workflow-engine/Dockerfile --tag "$GHCR_PREFIX/workflow-engine:$NEW_TAG" .
docker push "$GHCR_PREFIX/workflow-engine:$NEW_TAG"

docker build --file src/notification-svc/Dockerfile --tag "$GHCR_PREFIX/notification-svc:$NEW_TAG" .
docker push "$GHCR_PREFIX/notification-svc:$NEW_TAG"
```

**For cross-platform builds** (e.g., building on Mac ARM for x86 AKS):
```bash
docker buildx build --file src/expense-api/Dockerfile --platform linux/amd64 \
  --tag "$GHCR_PREFIX/expense-api:$NEW_TAG" --push .
```

**Redeploy the application:**
```bash
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry="$GHCR_PREFIX" \
  --parameters imageTag="$NEW_TAG" \
  --parameters deploymentTarget='radius'
```

**Or trigger GitHub Actions** by pushing to main:
```bash
git push origin main
```

---

## Next Steps

### Run the Demo Flow

Once the app is open in your browser:

1. **Submit a $50 expense** (auto-approve):
   - Fill in the form with amount = 50
   - Observe: status changes to "Approved" within seconds

2. **Submit a $150 expense** (manual review):
   - Fill in the form with amount = 150
   - Observe: status changes to "ManualReview" (not auto-rejected)

3. **Inspect the workflow logs:**
   ```bash
   export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
   kubectl logs -n "$WORKLOAD_NAMESPACE" -l app.kubernetes.io/name=workflow-engine --all-containers=true
   ```

4. **Inspect Dapr state:**
   ```bash
   export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
   kubectl exec -it deployment/expense-api -n "$WORKLOAD_NAMESPACE" -- \
     curl -s http://localhost:3500/v1.0/state/statestore | jq .
   ```

### Explore the Architecture

- **See the Radius app model:** `infra/radius/app.bicep`
- **See the environment definition:** `infra/radius/environments/azure-radius.bicep`
- **See the Azure recipes:** `infra/radius/recipes/azure/`
- **See the service code:** `src/`

---

## Teardown

When you are done with the RadiusClaim deployment and want to clean up all resources,
use [`scripts/teardown.sh`](../scripts/teardown.sh). The script removes Radius objects,
Kubernetes namespaces, and Azure resources in the correct dependency order and is safe
to run multiple times (idempotent).

**Quick start:**

```bash
# Preview what will be deleted (no changes made)
./scripts/teardown.sh --dry-run

# Tear down, keeping the resource group shell and service principals
./scripts/teardown.sh --resource-group radiusclaim-rg --yes

# Full teardown including the Azure resource group
./scripts/teardown.sh --resource-group radiusclaim-rg --include-resource-group --yes

# Also remove service principal app registrations
./scripts/teardown.sh --include-resource-group --include-service-principals --yes
```

**Key flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `--resource-group <name>` | `radiusclaim-rg` | Azure resource group to clean |
| `--kube-context <ctx>` | current context | Kubernetes context for kubectl/rad |
| `--include-resource-group` | off | Delete the entire resource group (not just its contents) |
| `--include-service-principals` | off | Delete `radiusclaim-radius-sp` and `radiusclaim-github-actions` app registrations |
| `--include-ghcr-artifacts` | off | Delete GHCR recipe and container images (requires `gh` CLI) |
| `--dry-run` | off | Print the plan without executing |
| `--yes` | off | Skip confirmation prompts |

⚠️ **Service principals are shared resources.** Only pass `--include-service-principals` if
you are certain no other environment or CI pipeline depends on them.

---

## Reference

- **README:** [`README.md`](../README.md)
- **Architecture Decision:** [`docs/ADR-0001-kubernetes-first-deployment.md`](ADR-0001-kubernetes-first-deployment.md)
- **Validation Checklist:** [`docs/radius-validation-checklist.md`](radius-validation-checklist.md)
- **Scripts:** [`scripts/README.md`](../scripts/README.md)
- **Radius Documentation:** https://docs.radapp.io/
- **Dapr Documentation:** https://docs.dapr.io/

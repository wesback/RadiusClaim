# End-to-End Setup: From Resource Group to Web Browser

> **Audience:** Platform engineers and operators deploying RadiusClaim to Azure  
> **Duration:** ~30–45 minutes (varies with Azure resource creation time)  
> **Goal:** Establish the complete infrastructure and deploy the app, then open the web UI in a browser

---

## Overview

This guide walks you through the entire RadiusClaim deployment pipeline from initial Azure setup to opening the application in a web browser. It covers both **what this repository automates** and **what you must do manually**.

### What's Automated
- Kubernetes cluster detection/validation (via Radius)
- Dapr and Radius control plane prerequisites checks (via CLI scripts)
- Container image builds and registry pushes (GitHub Actions)
- Radius environment and application deployment (GitHub Actions or local `rad` CLI)
- Kubernetes resource creation and Dapr component wiring (Radius + Bicep)
- Public endpoint exposure and DNS resolution (Radius gateway)

### What You Must Do Manually
1. Azure subscription selection and authentication
2. Resource group creation (if not using an existing one)
3. Kubernetes cluster provisioning (AKS, Arc-enabled, or self-managed) with Dapr + Radius prerequisites
4. GitHub Actions secret/variable configuration (if using CI/CD)
5. Radius workspace and group initialization (if running locally)
6. Opening the app URL in a browser

---

## Prerequisites

Before you start, confirm you have:

### Azure Account & CLI
```bash
# Install Azure CLI
# macOS: brew install azure-cli
# Windows/Linux: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

# Verify installation
az --version
# Expected: Azure CLI 2.60.0 or later
```

### Kubernetes Cluster with Dapr & Radius
You need a Kubernetes cluster with **Dapr and Radius already installed**. Options:

**Option A: Azure Kubernetes Service (AKS) — Recommended**
```bash
# If you don't have AKS yet, create it (see "Create AKS Cluster" section below)
# But you must install Dapr and Radius on it before deploying RadiusClaim
```

**Option B: Arc-enabled Kubernetes or Self-managed Cluster**
- Any Kubernetes cluster (on-premises, edge, or multi-cloud) reachable from your machine and registered with Azure Arc
- Or any self-managed Kubernetes cluster with Dapr and Radius control plane installed
- Must have Azure credentials configured (for Azure backing services)

### Dapr & Radius CLI
```bash
# Install Dapr CLI (for local development; optional if using only GitHub Actions)
# https://docs.dapr.io/getting-started/install-dapr-cli/

# Install Radius CLI (required for manual deployment)
wget -q https://raw.githubusercontent.com/radius-project/radius/main/deploy/install.sh -O - | /bin/bash
rad --version
# Expected: v0.37.0 or later
```

### Tools
```bash
# Required
- kubectl (Kubernetes CLI) — usually bundled with AKS/cluster tooling
- git (to clone this repo)
- docker (if building images locally instead of GitHub Actions)

# Optional (for validation scripts)
- jq (JSON processor)
- curl (HTTP client)

# For multi-platform builds (Mac ARM, Linux, Windows)
- docker buildx (usually included with Docker Desktop)
```

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

RadiusClaim's backing services (Blob Storage, Service Bus, Key Vault) live in a resource group.

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
Creates a logical container in Azure that will hold the backing services (Blob Storage, Service Bus, Key Vault) that Radius recipes provision. This is independent of the Kubernetes cluster itself.

---

## Step 3: Provision a Kubernetes Cluster (if needed)

If you already have a Kubernetes cluster with Dapr and Radius, skip to **Step 4**.

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
# Expected: radius-controller-manager, radius-dashboard (if enabled), etc. in Running state

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

# Verify it works
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
# Log in to GHCR
# Use the PAT created in the "Create a GitHub Personal Access Token" section above
export GITHUB_USERNAME="your-github-username"
export GHCR_TOKEN="ghp_xxxxxxxxxxxx"  # Your personal access token

echo "$GHCR_TOKEN" | docker login ghcr.io --username "$GITHUB_USERNAME" --password-stdin

# Clone or navigate to the RadiusClaim repository
cd /path/to/RadiusClaim

# Publish the recipes
export RECIPE_REGISTRY="ghcr.io/$GITHUB_USERNAME/radiusclaim/recipes"
export RECIPE_TAG="latest"

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
Packages the three custom Radius recipes (Azure Blob state store, Azure Service Bus pub/sub, Azure Key Vault secrets) as OCI artifacts in GHCR. The Radius environment definition references these URLs, so they must exist before `rad deploy` runs.

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
   - `RADIUS_KUBERNETES_NAMESPACE` — Kubernetes namespace (default: `radiusclaim-azure`)

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
   Public endpoint for expense-api: https://expense-api.<random-domain>.com
   ```

   Save this public endpoint URL.

### Option B: Manual Deployment with `rad` CLI

```bash
# Set environment variables
export GITHUB_USERNAME="your-github-username"
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_CLIENT_ID="<azure-service-principal-client-id>"
export AZURE_CLIENT_SECRET="<azure-service-principal-client-secret>"
export AZURE_RESOURCE_GROUP="radiusclaim-rg"
export AZURE_LOCATION="belgiumcentral"
export AZURE_TENANT_ID="<azure-tenant-id>"
export AZURE_PROVIDER_SCOPE="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP"
export RADIUS_ENVIRONMENT_NAME="azure"
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure"
export RECIPE_REGISTRY="ghcr.io/$GITHUB_USERNAME/radiusclaim/recipes"
export RECIPE_TAG="latest"

# Create or switch to the target environment (idempotent)
rad env create "$RADIUS_ENVIRONMENT_NAME" || true
rad env switch "$RADIUS_ENVIRONMENT_NAME"

# Register Azure provider credentials with the Radius control plane
# This enables Radius to authenticate with Azure when provisioning backing services (Blob Storage, Service Bus, Key Vault, etc.)
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
  --parameters location="$AZURE_LOCATION" \
  --parameters recipeRegistry="$RECIPE_REGISTRY" \
  --parameters recipeTag="$RECIPE_TAG"

# Verify the environment
rad env list
```

**What this does:**  
Deploys the Radius environment to your Kubernetes cluster. This creates:
- A Kubernetes namespace (`radiusclaim-azure`)
- Dapr component definitions (state store, pub/sub, secrets)
- Azure resource groups and backing services (Blob Storage, Service Bus, Key Vault) via Radius recipes

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

# Deploy the application
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry="$GHCR_PREFIX" \
  --parameters imageTag="$IMAGE_TAG" \
  --parameters deploymentTarget='radius'

# Wait for deployments to stabilize
kubectl rollout status deployment/expense-api -n radiusclaim-azure --timeout=5m
kubectl rollout status deployment/workflow-engine -n radiusclaim-azure --timeout=5m
kubectl rollout status deployment/notification-svc -n radiusclaim-azure --timeout=5m
```

**What this does:**  
Deploys the three RadiusClaim services (expense-api, workflow-engine, notification-svc) to the Kubernetes cluster with Dapr sidecars injected. The Radius app model wires them to the Dapr components created in Step 8.

---

## Step 10: Verify Deployment and Get the Public Endpoint

```bash
# Check that all services are running
kubectl get deployments -n radiusclaim-azure
# Expected: 3 deployments in Running state

kubectl get pods -n radiusclaim-azure
# Expected: 3+ pods (one per service)

# Get the public endpoint for expense-api (created by Radius Compute/routes resource)
kubectl get ingress -n radiusclaim-azure -o wide
# OR check Radius output from deployment logs

# If using GitHub Actions, the workflow output shows the endpoint
# If using rad CLI, check for the printed endpoint or extract manually:
EXPENSE_API_URL=$(kubectl get service expense-api -n radiusclaim-azure -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Expense API: http://$EXPENSE_API_URL"

# Fallback: Use port-forward if no external address is assigned
kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &
echo "Expense API (port-forward): http://127.0.0.1:8080"
```

**What this does:**  
Confirms that all services are running and obtains the public URL where the app is accessible.

---

## Step 11: Open the Web UI in a Browser

RadiusClaim includes a lightweight web UI for submitting expenses and viewing history.

```bash
# Open the app in your default browser
# Use the endpoint from Step 10

open "https://$EXPENSE_API_URL/app"
# or
open "http://127.0.0.1:8080/app"  # if using port-forward
```

**What you'll see:**
- A form to submit an expense (amount, description, employee ID)
- Recent expense history with status (Submitted, Approved, Rejected)
- Workflow correlation IDs and telemetry information
- Live updates as the workflow processes expenses

---

## Step 12: Validate the Deployment

Use the included validation script to confirm the full flow works:

```bash
# Run the validation script
./scripts/validate-deployment.sh "https://$EXPENSE_API_URL"
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
kubectl logs -n radius-system -l app.kubernetes.io/name=radius-controller-manager --tail=50

# Restart the control planes if needed
kubectl rollout restart deployment/dapr-sidecar-injector -n dapr-system
kubectl rollout restart deployment/radius-controller-manager -n radius-system
```

### Recipes Not Published

**Symptom:** `rad deploy` fails with "recipe not found" or registry errors

**Solution:**
```bash
# Verify GHCR login
docker login ghcr.io --username "$GITHUB_USERNAME"

# Manually publish recipes
./scripts/publish-radius-recipes.sh "$RECIPE_REGISTRY" "$RECIPE_TAG"

# Verify images exist in GHCR
docker pull "$RECIPE_REGISTRY/state-store:$RECIPE_TAG"
```

### Services Not Starting

**Symptom:** `kubectl get pods -n radiusclaim-azure` shows pending or crash-looping pods

**Solution:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n radiusclaim-azure

# Check logs
kubectl logs <pod-name> -n radiusclaim-azure

# Verify images are accessible
docker pull "$GHCR_PREFIX/expense-api:$IMAGE_TAG"

# Check resource quotas
kubectl describe resourcequota -n radiusclaim-azure
```

### Public Endpoint Not Assigned

**Symptom:** `kubectl get ingress/svc` shows `<pending>` for external IP/hostname

**Solution:**
```bash
# Use port-forward as a temporary alternative
kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &
# Access via http://127.0.0.1:8080

# Check Radius route resource
kubectl get route -n radiusclaim-azure

# Check load balancer status
kubectl get svc expense-api -n radiusclaim-azure -w  # Watch for address assignment
```

### Validation Script Fails

**Symptom:** `./scripts/validate-deployment.sh` reports failures

**Solution:**
```bash
# Verify the URL is reachable
curl "https://$EXPENSE_API_URL/healthz"

# Check if jq is installed
jq --version
# If not: brew install jq (or apt-get install jq)

# Run with verbose output to see which step fails
bash -x ./scripts/validate-deployment.sh "https://$EXPENSE_API_URL"
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
   kubectl logs -n radiusclaim-azure -l app=workflow-engine --all-containers=true
   ```

4. **Inspect Dapr state:**
   ```bash
   kubectl exec -it deployment/expense-api -n radiusclaim-azure -- \
     curl -s http://localhost:3500/v1.0/state/statestore | jq .
   ```

### Explore the Architecture

- **See the Radius app model:** `infra/radius/app.bicep`
- **See the environment definition:** `infra/radius/environments/azure-radius.bicep`
- **See the Azure recipes:** `infra/radius/recipes/azure/`
- **See the service code:** `src/`

### Deploy Changes

To redeploy after code changes:

```bash
# Rebuild and push images (using native build, which matches your local machine architecture)
docker build --file src/expense-api/Dockerfile --tag "$GHCR_PREFIX/expense-api:$NEW_TAG" .
docker push "$GHCR_PREFIX/expense-api:$NEW_TAG"

# Or, if deploying to a different architecture, use docker buildx with --platform:
# docker buildx build --file src/expense-api/Dockerfile --platform linux/amd64 --tag "$GHCR_PREFIX/expense-api:$NEW_TAG" --push .

# Redeploy the app
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry="$GHCR_PREFIX" \
  --parameters imageTag="$NEW_TAG"

# Or trigger GitHub Actions by pushing to main
git push origin main
```

---

## Reference

- **README:** [`README.md`](../README.md)
- **Architecture Decision:** [`docs/ADR-0001-kubernetes-first-deployment.md`](ADR-0001-kubernetes-first-deployment.md)
- **Demo Walkthrough:** [`docs/phase-7-demo-walkthrough.md`](phase-7-demo-walkthrough.md)
- **Validation Checklist:** [`docs/radius-validation-checklist.md`](radius-validation-checklist.md)
- **Scripts:** [`scripts/README.md`](../scripts/README.md)
- **Radius Documentation:** https://docs.radapp.io/
- **Dapr Documentation:** https://docs.dapr.io/

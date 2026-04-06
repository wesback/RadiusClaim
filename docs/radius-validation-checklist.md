# Kubernetes + Radius Deployment Validation Checklist

> **Purpose:** Pre-deployment validation and troubleshooting guide for Kubernetes + Radius deployment  
> **Audience:** Platform engineers deploying via `rad deploy` to Kubernetes (AKS or any K8s with Dapr and Radius)  
> **Scope:** Phase 7 validation requirements

> **Start here for the full operator flow:** Use [`docs/end-to-end-setup-walkthrough.md`](./end-to-end-setup-walkthrough.md) if you need the resource-group-to-browser journey. Keep this checklist open as the companion preflight and troubleshooting reference.
>
> **First-time cluster prep:** `./scripts/prepare-cluster.sh` owns the cluster boundary (AKS verify/create, `kubectl` context, Dapr, Radius). On a fresh cluster, include `--install-dapr --install-radius`. `./scripts/bootstrap.sh` is the repeatable deploy step after that. RadiusClaim uses **workload identity** (Azure Entra OIDC federated credentials) for all authentication — no client secrets are stored in the cluster.

---

## Prerequisites Validation

Before running `rad deploy`, verify these requirements are met:

### ✅ Radius Control Plane

```bash
# Verify Radius CLI is installed
rad --version
# Expected: v0.x.x or later

# Verify the Radius controller is running
kubectl get pods -n radius-system -l app.kubernetes.io/name=controller
# Expected: controller pod in Running state
```

### ✅ Kubernetes Cluster Access

```bash
# Verify kubectl context
kubectl config current-context
# Expected: Your target Kubernetes cluster

# Verify namespace exists (or will be created)
kubectl get namespace radiusclaim-azure || echo "Will be created during deployment"

# Verify cluster connectivity
kubectl cluster-info
# Expected: Cluster endpoint and services responding
```

### ✅ Azure Provider Configuration

```bash
# Verify Azure subscription access
az account show --query '{subscription:id,tenant:tenantId}' -o table
# Expected: Your subscription and tenant IDs

# Verify resource group exists
az group show --name <your-resource-group> --query '{name:name,location:location}' -o table
# Expected: Resource group details or 404 (will be created)

# Test Azure credentials
az account get-access-token --query 'accessToken' -o tsv > /dev/null && echo "✅ Azure credentials valid"
```

### ✅ GitHub Actions Secrets/Variables

For CI/CD deployment, verify these are configured:

**Required Secrets:**
```bash
# AZURE_SUBSCRIPTION_ID (also a variable for clarity)
# AZURE_CLIENT_ID (managed identity client ID for rad credential register azure wi)
# AZURE_TENANT_ID (for rad credential register azure wi)
# RADIUS_KUBECONFIG (raw kubeconfig content for the Kubernetes cluster with Radius)
```

> **Auth model:** `AZURE_CLIENT_SECRET` is used by the CI workflow (`deploy-azure.yml`) to register service principal credentials with Radius via `rad credential register azure sp`. Local bootstrap defaults to workload identity (`--azure-auth-mode wi` or `auto`), which does not need a client secret. See the CI workflow for the exact registration call.

**Required Variables:**
```bash
# AZURE_LOCATION (e.g., belgiumcentral, westus2) — for Azure backing services
# AZURE_RESOURCE_GROUP (e.g., radiusclaim-rg) — for Azure backing services
```

**Optional Variables:**
```bash
# RADIUS_KUBERNETES_CONTEXT (kubectl context name, optional)
# RADIUS_KUBERNETES_NAMESPACE (default: radiusclaim-azure)
```

To verify in GitHub:
1. Navigate to repository **Settings** → **Secrets and variables** → **Actions**
2. Check that all required secrets and variables are present
3. Verify `RADIUS_KUBERNETES_CONTEXT` (optional) or leave unset to use current context
4. Verify `RADIUS_KUBERNETES_NAMESPACE` (optional, defaults to `radiusclaim-azure`)

If you have not registered the managed identity with Radius yet, ensure the AKS cluster has OIDC issuer and workload identity enabled, then register the managed identity client ID:

```bash
export AZURE_RESOURCE_GROUP="radiusclaim-rg"
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# Verify the managed identity exists (created by deploy-dapr-components-workload-identity.sh)
az identity show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name radiusclaim-workload-identity \
  --query '{clientId:clientId,principalId:principalId}' \
  -o jsonc

# Register the managed identity client ID with Radius (workload identity, no secret)
rad credential register azure wi \
  --client-id "<managed-identity-client-id>" \
  --tenant-id "<azure-tenant-id>"
```

Map values from the identity output to GitHub Secrets as follows:
- `clientId` → `AZURE_CLIENT_ID`
- Subscription ID from `az account show` → `AZURE_SUBSCRIPTION_ID`
- Tenant ID from `az account show --query tenantId -o tsv` → `AZURE_TENANT_ID`

---

## Understanding Namespace Roles

Before running any deployment or validation commands, know the two namespaces:

```bash
# Environment namespace — holds the Radius environment and backing-service definitions.
# Do NOT run kubectl pod/log/component commands here; workloads don't live here.
export ENVIRONMENT_NAMESPACE="radiusclaim-azure"

# Workload namespace — holds the three services, Dapr sidecars, and Dapr Component CRDs.
# ALL pod, log, component, and port-forward commands target this namespace.
export WORKLOAD_NAMESPACE="azure-radiusclaim"
```

> Radius creates the workload namespace automatically by appending the application name (`radiusclaim`) to the environment namespace (`radiusclaim-azure`). If you used a different environment namespace, adjust `WORKLOAD_NAMESPACE` accordingly.

---

## Bicep Validation

Validate all Radius Bicep files parse correctly:

```bash
# Validate application model
az bicep build --file infra/radius/app.bicep
# Expected: No output (success) or ARM template JSON

# Validate Radius environment
az bicep build --file infra/radius/environments/azure-radius.bicep
# Expected: No output (success)

# Validate Azure recipes
az bicep build --file infra/radius/recipes/azure/state-store.bicep
az bicep build --file infra/radius/recipes/azure/pubsub.bicep
az bicep build --file infra/radius/recipes/azure/secrets.bicep
# Expected: No output for all three
```

If validation fails, check:
- Bicep CLI version: `az bicep version` (should be v0.30.0+)
- Radius extension version in Bicep files matches installed Radius version
- `infra/radius/app.bicep` should compile without `Radius.Compute/*` `BCP081` warnings on stock Radius 0.55
- Recipe parameter types match what `infra/radius/app.bicep` provides

---

## Pre-Deployment Checks

### ✅ Container Images

If deploying manually (not via CI/CD), verify images are available:

```bash
# Check GHCR images exist (for CI/CD built images)
docker pull ghcr.io/<your-org>/radiusclaim/expense-api:<tag>
docker pull ghcr.io/<your-org>/radiusclaim/workflow-engine:<tag>
docker pull ghcr.io/<your-org>/radiusclaim/notification-svc:<tag>
```

For local testing, you can build and push images manually:

```bash
# From repository root
docker build -f src/expense-api/Dockerfile -t ghcr.io/<your-org>/radiusclaim/expense-api:local .
docker build -f src/workflow-engine/Dockerfile -t ghcr.io/<your-org>/radiusclaim/workflow-engine:local .
docker build -f src/notification-svc/Dockerfile -t ghcr.io/<your-org>/radiusclaim/notification-svc:local .

# Push to registry
docker push ghcr.io/<your-org>/radiusclaim/expense-api:local
docker push ghcr.io/<your-org>/radiusclaim/workflow-engine:local
docker push ghcr.io/<your-org>/radiusclaim/notification-svc:local
```

### ✅ Radius Recipe Artifacts

Publish the custom recipe Bicep files before deploying the Radius environment:

```bash
# Set GHCR credentials (publish script will auto-authenticate)
export GHCR_TOKEN="ghp_your_token_here"
export GITHUB_USERNAME="your-github-username"

# Or pre-authenticate manually
# docker login ghcr.io

./scripts/publish-radius-recipes.sh ghcr.io/<your-org>/radiusclaim/recipes <your-tag>
```

**Why:** Radius recipe `templatePath` values are OCI references. Local relative paths under `infra/radius/recipes/azure/` are source files for authoring, not deployable recipe addresses.

### ✅ Radius Workspace and Group

```bash
# Verify Radius workspace exists or create it
rad workspace list
# Expected: Your workspace name appears

# If not present, create it:
rad workspace create kubernetes <workspace-name> --context <kubectl-context>

# Switch to workspace
rad workspace switch <workspace-name>

# Create Radius group if needed
rad group create radiusclaim -w <workspace-name>
rad group switch radiusclaim -w <workspace-name>
```

### ✅ Azure Provider Credentials (Required for Azure-Backed Recipes)

**Before deploying an environment with Azure backing services, register the managed identity credential with Radius using workload identity:**

```bash
# Register Azure workload identity credentials with the active Radius workspace.
# This enables Radius to provision Azure resources (PostgreSQL, Service Bus, Key Vault, etc.)
# No client secret is required — authentication uses OIDC federated credentials.
rad credential register azure wi \
  --client-id "$AZURE_CLIENT_ID" \
  --tenant-id "$AZURE_TENANT_ID"

# Verify the credential was registered
rad credential list
# Expected: Shows azure credential with status
```

**Prerequisites for workload identity mode:**
- AKS cluster must have OIDC issuer enabled: `az aks show -g <rg> -n <cluster> --query oidcIssuerProfile`
- AKS cluster must have workload identity addon enabled: `az aks show -g <rg> -n <cluster> --query securityProfile.workloadIdentity`
- Managed identity `radiusclaim-workload-identity` must exist in the resource group
- `AZURE_CLIENT_ID` must be the managed identity's **client ID** (not a service principal app ID)

**Why this matters:**
- Radius uses the registered credential to authenticate with Azure when deploying recipes
- Without this step, `rad deploy infra/radius/environments/azure-radius.bicep` will fail with a missing `azure-azurecloud-default` secret error
- The credential is stored securely in the Radius control plane, not in your environment variables
- Each workspace must have the Azure credential registered independently

**For CI/CD (GitHub Actions):**
- The workflow automatically handles this by running `rad credential register azure wi ...` before deploying the environment
- See `.github/workflows/deploy-azure.yml` for the implementation

---

## Deployment Steps

For the scripted operator path, use `./scripts/prepare-cluster.sh` once per cluster, then `./scripts/bootstrap.sh --resource-group <your-resource-group>` for each repeatable deployment. The steps below are the explicit equivalent when you want to inspect or troubleshoot each Radius action individually.

### Step 1: Create Target Environment (Idempotent)

Create or switch to the target environment name directly:

```bash
rad env create azure || true
rad env switch azure
```

**Note:** `rad deploy` on an environment Bicep will update the environment configuration. No temporary bootstrap environment is needed.

### Step 2: Register Azure Provider Credentials

Before deploying the Azure environment with recipes, ensure the workload identity credential is registered with Radius:

```bash
# Register Azure workload identity credentials (no client secret required)
rad credential register azure wi \
  --client-id "$AZURE_CLIENT_ID" \
  --tenant-id "$AZURE_TENANT_ID"

# Verify the credential is registered
rad credential list
# Expected: Shows azure provider in the list
```

**Critical:** If you skip this step, the environment deployment will fail when Radius tries to provision Azure resources via recipes.

For the tenant-compliant statestore path, also resolve the managed identity object ID that should receive Blob data-plane RBAC:

```bash
export AZURE_PRINCIPAL_ID="${AZURE_PRINCIPAL_ID:-$(az identity show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name radiusclaim-workload-identity \
  --query principalId -o tsv)}"
```

### Step 3: Publish Radius Recipe Artifacts

```bash
# Set GHCR credentials (publish script will auto-authenticate)
export GHCR_TOKEN="ghp_your_token_here"
export GITHUB_USERNAME="your-github-username"

# Or pre-authenticate manually
# docker login ghcr.io

./scripts/publish-radius-recipes.sh ghcr.io/<your-org>/radiusclaim/recipes <your-tag>
```

### Step 4: Deploy Azure Environment

```bash
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters @infra/radius/environments/azure-radius.parameters.json \
  --parameters environmentName=azure \
  --parameters kubernetesNamespace=radiusclaim-azure \
  --parameters azureProviderScope="/subscriptions/<subscription-id>/resourceGroups/<resource-group>" \
  --parameters location=<azure-location> \
  --parameters daprAzureClientId="$AZURE_CLIENT_ID" \
  --parameters daprAzurePrincipalId="$AZURE_PRINCIPAL_ID" \
  --parameters daprAzureTenantId="$AZURE_TENANT_ID" \
  --parameters recipeRegistry='ghcr.io/<your-org>/radiusclaim/recipes' \
  --parameters recipeTag='<your-tag>'
```

**Expected output:**
```
Building infra/radius/environments/azure-radius.bicep...
Deploying template 'infra/radius/environments/azure-radius.bicep' for application...
Deployment Complete

Resources:
  env       Applications.Core/environments
```

**Validation:**
```bash
# Switch to the new environment
rad env switch azure

# List environment details
rad env show azure
# Expected: Shows compute kind as kubernetes, namespace, and Azure provider scope
```

### Step 5: Deploy Application Model

```bash
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry='ghcr.io/<your-org>/radiusclaim' \
  --parameters imageTag='<your-tag>' \
  --parameters deploymentTarget='radius'
```

**Important:** Use the same published tag you just verified or pushed. `infra/radius/app.bicep` intentionally no longer falls back to the retired `phase1` tag, because that default was sending clusters to stale GHCR packages.

**Expected output:**
```
Building infra/radius/app.bicep...
Deploying template 'infra/radius/app.bicep' for application 'radiusclaim'...
Deployment Complete

Resources:
  app                     Applications.Core/applications
  statestore              Applications.Dapr/stateStores
  pubsub                  Applications.Dapr/pubSubBrokers
  platform-secrets        Applications.Dapr/secretStores
  expense-api-service     Applications.Core/containers
  workflow-engine-service Applications.Core/containers
  notification-service    Applications.Core/containers

Public endpoint http://expense.radiusclaim.<platform-address>.nip.io/
```

The `Public endpoint ...` line is the preferred base URL for the hosted `/app` UI and the `expense-api` HTTP endpoints. Radius keeps `workflow-engine` and `notification-svc` internal; they should still be observed through Kubernetes logs, not exposed directly.

**Validation:**
```bash
# Check Kubernetes resources were created in the WORKLOAD namespace
kubectl get pods -n "$WORKLOAD_NAMESPACE"
# Expected: expense-api, workflow-engine, notification-svc pods in Running state

# Check Dapr components exist in the WORKLOAD namespace (where sidecars can see them)
kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets components
#
# ⚠️ If "No resources found": Radius reported success but did not project Dapr Component CRDs.
# This is the component projection gap. Run the backfill (Step 5a below).
```

### Step 5a: Verify Dapr Components (bootstrap) / Apply Components (manual path)

> **Bootstrap path:** `bootstrap.sh` runs `apply-dapr-components-from-recipes.sh` automatically. If bootstrap completed without errors, skip to "Verify Components" below.
> **Manual `rad deploy` path:** components are not created automatically — run the script below.

Radius may report `Applications.Dapr/*` as Succeeded without projecting `components.dapr.io` CRDs into Kubernetes. `bootstrap.sh` compensates for this automatically; the script can also be run manually.

```bash
kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets
#
# If "No resources found" → apply components:

export AZURE_CLIENT_ID="<managed-identity-client-id>"   # from: az identity show --name radiusclaim-workload-identity --query clientId
export AZURE_TENANT_ID="<azure-tenant-id>"              # from: az account show --query tenantId

./scripts/apply-dapr-components-from-recipes.sh \
  --environment azure \
  --application radiusclaim \
  --namespace "$WORKLOAD_NAMESPACE" \
  --tenant-id "$AZURE_TENANT_ID" \
  --client-id "$AZURE_CLIENT_ID"

# After applying, restart pods so sidecars pick up the new components:
kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc \
  -n "$WORKLOAD_NAMESPACE"
```

`apply-dapr-components-from-recipes.sh` reads Azure resource IDs from Radius `outputResources`, then creates `statestore`, `pubsub`, and `platform-secrets` components using workload identity (OIDC token exchange — no `azureClientSecret` in the cluster).

**Verify Components:**
```bash
kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets

kubectl logs -n "$WORKLOAD_NAMESPACE" deployment/expense-api -c daprd --tail=20 | grep "Component loaded"
# Expected: Lines showing statestore and pubsub loaded
```

---

## Post-Deployment Validation

### ✅ Pod Health

```bash
# Check all pods are Running (use WORKLOAD namespace, not environment namespace)
kubectl get pods -n "$WORKLOAD_NAMESPACE"
# Expected: 3 pods with STATUS = Running

# Check pod logs for startup errors (Radius uses app.kubernetes.io/name label)
kubectl logs -n "$WORKLOAD_NAMESPACE" -l app.kubernetes.io/name=expense-api --tail=50
kubectl logs -n "$WORKLOAD_NAMESPACE" -l app.kubernetes.io/name=workflow-engine --tail=50
kubectl logs -n "$WORKLOAD_NAMESPACE" -l app.kubernetes.io/name=notification-svc --tail=50
# Expected: No error messages, Dapr sidecar initialized
```

### ✅ Dapr Component Registration

```bash
# Verify Dapr components are registered in the WORKLOAD namespace
kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets

# Check component configuration
kubectl describe component statestore -n "$WORKLOAD_NAMESPACE"
kubectl describe component pubsub -n "$WORKLOAD_NAMESPACE"
kubectl describe component platform-secrets -n "$WORKLOAD_NAMESPACE"
# Expected:
# - statestore => state.azure.blobstorage / v2
# - pubsub => pubsub.azure.servicebus.topics / v1
# - platform-secrets => secretstores.azure.keyvault / v1
#
# If "No resources found": Run the backfill step (Step 5a above).
```

### ✅ Azure Backing Resources

```bash
# Verify Storage Account for state store
az storage account list --resource-group <your-resource-group> --query "[?contains(name, 'ce')].{name:name,location:location}" -o table
# Expected: At least one storage account (created by recipe)

# Verify Service Bus namespace for pub/sub
az servicebus namespace list --resource-group <your-resource-group> --query "[].{name:name,location:location}" -o table
# Expected: Service Bus namespace (created by recipe)

# Verify the topic and subscriber-specific subscription used by the demo
az servicebus topic list --resource-group <your-resource-group> --namespace-name <service-bus-namespace> --query "[].name" -o table
az servicebus topic subscription list --resource-group <your-resource-group> --namespace-name <service-bus-namespace> --topic-name expense-notifications --query "[].name" -o table
# Expected: topic expense-notifications and subscription notification-svc

# Verify Key Vault for secrets
az keyvault list --resource-group <your-resource-group> --query "[].{name:name,location:location}" -o table
# Expected: Key Vault (created by recipe)
```

### ✅ Service Connectivity

Preferred path: use the public Radius gateway emitted by `rad deploy`.

```bash
# Test the public endpoint printed by rad deploy
curl https://<expense-api-base-url>/healthz
# Expected: {"status":"ok"}

# Fallback if the cluster does not yet have a public address:
kubectl port-forward -n "$WORKLOAD_NAMESPACE" svc/expense-api 8080:8080 &
FORWARD_PID=$!

curl http://localhost:8080/healthz
# Expected: {"status":"ok"}
# If connection refused: pods may not be running yet. Check: kubectl get pods -n "$WORKLOAD_NAMESPACE"

# Stop port-forward
kill $FORWARD_PID
```

---

## End-to-End Validation

**IMPORTANT:** This requires a live Radius environment with deployed services. The preferred path is the public Radius gateway for `expense-api`; use `kubectl port-forward` only as a fallback when the public endpoint is not yet reachable from your workstation.

If a live environment is available, run the shared validation script against the public `expense-api` base URL:

```bash
./scripts/validate-deployment.sh https://<expense-api-base-url>

# Fallback when the gateway address is unavailable or still propagating:
kubectl port-forward -n "$WORKLOAD_NAMESPACE" svc/expense-api 8080:8080 &
FORWARD_PID=$!
./scripts/validate-deployment.sh http://127.0.0.1:8080
kill $FORWARD_PID

kubectl logs -n "$WORKLOAD_NAMESPACE" deployment/notification-svc -c notification-svc --tail=200
```

Then confirm the same observable outcomes described in the [Phase 7 Demo Walkthrough](./phase-7-demo-walkthrough.md):

1. Submit a $50 expense (auto-approve flow)
2. Verify status progresses: Submitted → Approved → Reimbursed
3. Submit a $150 expense (manual-review flow)
4. Verify status progresses: Submitted → ManualReviewRequested
5. Check `notification-svc` logs for both events via `kubectl logs`
6. Verify CorrelationId traceability

**If no live environment is available:**

Document the following in the deployment report:
```
✅ Bicep validation: All files parse correctly
✅ Kubernetes readiness: Pods running, Dapr components registered
✅ Azure backing resources: Storage, Service Bus, Key Vault provisioned
⚠️  End-to-end validation: Requires live Radius environment (not available in this environment)
   → Recommend manual validation after deployment to target cluster
   → Follow steps in docs/phase-7-demo-walkthrough.md
```

---

## Troubleshooting

### Issue: `rad deploy` fails with "environment not found"

**Cause:** Environment needs to exist before deploying (addressed by idempotent pattern).

**Solution:**
```bash
# Create environment if it doesn't exist (idempotent)
rad env create azure || true
rad env switch azure
# Then retry deployment
```

**Note:** GitHub Actions workflow now handles this automatically.

### Issue: `rad deploy` fails with "missing `azure-azurecloud-default` secret" or "recipe provisioning failed"

**Cause:** The Azure credential was not registered with the Radius control plane before deploying the environment with Azure-backed recipes.

**Solution:**
```bash
# Register Azure workload identity credentials with Radius (no client secret required)
rad credential register azure wi \
  --client-id "$AZURE_CLIENT_ID" \
  --tenant-id "$AZURE_TENANT_ID"

# Verify the credential was registered
rad credential list
# Expected: Shows 'azure' provider in the list

# Then retry the environment deployment
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters @infra/radius/environments/azure-radius.parameters.json \
  --parameters environmentName=azure \
  --parameters kubernetesNamespace=radiusclaim-azure \
  --parameters azureProviderScope="/subscriptions/<subscription-id>/resourceGroups/<resource-group>" \
  --parameters location=<azure-location> \
  --parameters recipeRegistry='ghcr.io/<your-org>/radiusclaim/recipes' \
  --parameters recipeTag='<your-tag>'
```

**Critical:** This step must be completed before deploying the Radius environment when using Azure-backed recipes. The GitHub Actions workflow includes this step automatically after environment creation.

### Issue: `rad deploy` fails with `InvalidResourceNamespace` for `Radius.Compute/containers`

**Cause:** The target Radius control plane is running the stock 0.55 application catalog, which expects `Applications.Core/containers` and `Applications.Core/gateways` for app services and ingress. Preview `Radius.Compute/*` resources are not registered there.

**Solution:**
```bash
# Verify the application model uses stock resource types
az bicep build --file infra/radius/app.bicep
# Expected: no Radius.Compute namespace warnings

# Then redeploy the application model
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry='ghcr.io/<your-org>/radiusclaim' \
  --parameters imageTag='<your-tag>' \
  --parameters deploymentTarget='radius'
```

**Exact pivot:** `Applications.Core/containers` ↔ `Radius.Compute/containers` and `Applications.Core/gateways` ↔ `Radius.Compute/routes`. On stock Radius 0.55, stay on the `Applications.Core/*` side unless your platform team has explicitly installed a preview catalog that documents the `Radius.Compute/*` types.

### Issue: Pods remain in `Pending` state

**Cause:** Kubernetes cluster lacks resources or image pull fails.

**Solution:**
```bash
# Check pod events (use WORKLOAD namespace)
kubectl describe pod <pod-name> -n "$WORKLOAD_NAMESPACE"
# Look for ImagePullBackOff, resource limits, or scheduling failures

# Verify images are accessible
kubectl run test-pull --image=ghcr.io/<your-org>/radiusclaim/expense-api:<tag> --command -- sleep 3600
kubectl delete pod test-pull
```

If the pod event shows `ghcr.io/sovereignapp/radiusclaim/*:phase1`, redeploy with the current repo namespace and a tag you actually pushed:

```bash
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry='ghcr.io/<your-github-username>/radiusclaim' \
  --parameters imageTag='<published-tag>' \
  --parameters deploymentTarget='radius'
```

If the image reference already points at `ghcr.io/<your-username>/...` and Kubernetes still reports `403 Forbidden`, the remaining blocker is GHCR package visibility or pull auth rather than Radius wiring. Either make the package public in GHCR, or wire a pull secret on the workload namespace:

```bash
export GHCR_TOKEN='<github-pat-with-read:packages>'

# Pull secrets belong in the WORKLOAD namespace, not the environment namespace
kubectl create secret docker-registry ghcr-pull \
  --namespace "$WORKLOAD_NAMESPACE" \
  --docker-server=ghcr.io \
  --docker-username="$(gh api user --jq .login)" \
  --docker-password="$GHCR_TOKEN"

# RadiusClaim pods use NAMED service accounts, not 'default'.
# Patch each one individually — patching 'default' alone will not resolve ErrImagePull.
for SA in expense-api workflow-engine notification-svc; do
  kubectl patch serviceaccount "$SA" \
    --namespace "$WORKLOAD_NAMESPACE" \
    --type merge \
    -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
done
```

### Issue: Dapr components not registering

**Cause:** Radius may report `Applications.Dapr/*` resources as Succeeded without projecting `components.dapr.io` CRDs to Kubernetes. This is a known component projection gap.

**First Check — Do components exist in the workload namespace?**
```bash
# Components must be in the WORKLOAD namespace (where sidecars run), not the environment namespace
kubectl get components.dapr.io -n "$WORKLOAD_NAMESPACE"
# Expected: statestore, pubsub, platform-secrets
#
# If "No resources found": the projection gap is confirmed. Run the backfill below.
# If components exist but sidecars still fail: check sidecar logs (see "Services return 500 errors").
```

**Fix — Run the component script:**
```bash
./scripts/apply-dapr-components-from-recipes.sh \
  --environment azure \
  --application radiusclaim \
  --namespace "$WORKLOAD_NAMESPACE" \
  --tenant-id "$AZURE_TENANT_ID" \
  --client-id "$AZURE_CLIENT_ID"

# Restart pods so sidecars pick up the new components
kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc \
  -n "$WORKLOAD_NAMESPACE"
```

**Alternative manual fix — If the script prerequisites are not met:**
1. Ensure the Radius environment and app are deployed (`rad env list`, `rad app list`)
2. Ensure Azure credentials are registered (`rad credential list`)
3. Re-run `rad deploy infra/radius/app.bicep ...` once to rule out staleness
4. If `kubectl get components.dapr.io -A` is still empty, run `apply-dapr-components-from-recipes.sh`

### Issue: `daprd` is in `CrashLoopBackOff`

**Cause:** The sidecar is loading a broken Dapr component, which is a platform wiring issue rather than an app-container issue. In the live RadiusClaim Azure slice, the highest-signal failure is an invalid statestore auth path (`KeyBasedAuthenticationNotPermitted`) after a manual component backfill.

**Confirm:**
```bash
export WORKLOAD_NAMESPACE="azure-radiusclaim"
POD=$(kubectl get pods -n "$WORKLOAD_NAMESPACE" --no-headers | awk '/expense-api/ {print $1; exit}')

kubectl logs -n "$WORKLOAD_NAMESPACE" "$POD" -c daprd --previous --tail=120
kubectl get component statestore pubsub -n "$WORKLOAD_NAMESPACE" -o yaml
```

**Interpretation:**
- `KeyBasedAuthenticationNotPermitted` in `daprd` logs → `statestore` is using account-key authentication, but the backing storage account disallows shared-key access (Azure Policy). This means the Dapr component was **not properly configured for workload identity**. The backfill script should have created a workload-identity-based component — if it didn't, rerun the backfill.
- `pubsub` metadata includes `connectionString` instead of `namespaceName` + `azureClientId` → the pub/sub component is using the legacy connection string path instead of workload identity. Re-run `apply-dapr-components-from-recipes.sh` to patch it to workload identity.
- Dapr annotations such as `dapr.io/enabled`, `dapr.io/app-id`, and `dapr.io/app-port` are **not** the problem when the sidecar dies during component initialization.

**Fix path:**

Rerun the component script to ensure all Dapr components are configured with workload identity:
```bash
./scripts/apply-dapr-components-from-recipes.sh \
  --environment azure \
  --application radiusclaim \
  --namespace "$WORKLOAD_NAMESPACE" \
  --tenant-id "$AZURE_TENANT_ID" \
  --client-id "$AZURE_CLIENT_ID"

kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc \
  -n "$WORKLOAD_NAMESPACE"
```

**Important:** All components must use workload identity (OIDC token exchange). Shared-key authentication is **not supported** and is blocked by Azure Policy in tenant environments. If you encounter shared-key errors, it indicates the components were not properly configured with workload identity. Rerun the backfill script to fix this.

### Issue: Services return 500 errors

**Cause:** Dapr sidecar not initialized or component wiring broken.

**Solution:**
```bash
# Check Dapr sidecar logs (use WORKLOAD namespace)
kubectl logs -n "$WORKLOAD_NAMESPACE" <pod-name> -c daprd

# Verify Dapr sidecar is present in the pod
kubectl get pod <pod-name> -n "$WORKLOAD_NAMESPACE" -o jsonpath='{.spec.containers[*].name}'
# Expected: Container names include "daprd"
#
# If daprd only loads "kubernetes (secretstores.kubernetes/v1)" and never loads statestore/pubsub,
# the issue is missing Dapr Component CRDs. Run the backfill (Step 5a in Deployment Steps).
```

### Issue: Deployment fails: "a vault with the same name already exists in deleted state"

**Cause:** Azure Key Vault soft-delete collision. When a Key Vault is deleted, Azure reserves the name for 7 days before automatic purge. Our Radius recipe generates vault names **deterministically** using `uniqueString()`, so the same environment always tries to create the same vault name.

**Scripted path behavior (`./scripts/bootstrap.sh`):**
- Bootstrap now resolves the exact deterministic Key Vault name for `platform-secrets` before app deployment.
- If that vault is soft-deleted **in the same subscription, resource group, and location**, bootstrap prompts to restore it and then reuses it.
- If Azure can only recover the deleted vault into some other scope, bootstrap fails early with that scope called out explicitly instead of letting `rad deploy infra/radius/app.bicep` fail unclearly.

**Diagnosis:**
```bash
# List soft-deleted vaults
az keyvault list-deleted

# Find your vault and note the scheduledPurgeDate
# Expected output shows a vault like "ce-ghhsgdsk4etcc" with a future purge date
```

**Solution — Option A (Recommended when scope matches: Restore the deleted vault)**
1. Confirm the deleted vault belongs to the same subscription/resource group/location that bootstrap or your manual deployment targets
2. Restore it:
   ```bash
   az keyvault recover --name ce-<vault-suffix> --location <region>
   ```
3. Retry `./scripts/bootstrap.sh --resource-group <name>` or `rad deploy`
4. Re-apply any required runtime RBAC afterward (the repo's Dapr backfill step already repairs the Key Vault Secrets User assignment)

**Solution — Option B (If restore is not safe/possible: Wait for Auto-Purge or Purge Manually)**
1. Note the `scheduledPurgeDate` from `az keyvault list-deleted`
2. If you own the deleted vault and understand the impact, purge it:
   ```bash
   az keyvault purge --name ce-<vault-suffix> --location <region>
   ```
3. Otherwise wait until the scheduled purge date passes
4. Retry deployment after the name is free again

**Solution — Option C (Immediate isolation: Use New Environment)**
1. Create a new Radius environment with a different name:
   ```bash
   rad env create <new-environment-name> --namespace radiusclaim-azure
   rad env switch <new-environment-name>
   ```
2. Deploy using the new environment — `uniqueString()` will generate a new vault name
3. Update team runbooks to reference the new environment name

**Prevention:** This is normal Azure behavior and not a code bug. Document any custom environment names in your runbooks so future operators understand the soft-delete window.

---

## Known Gaps (Phase 7)

The following gaps are documented and **not considered blocking** for Phase 7 completion:

1. **Live end-to-end validation:** Requires a deployed Radius environment with reachable `expense-api` access (public Radius gateway preferred, local `kubectl port-forward` fallback). If unavailable, structural validation (Bicep parse, pod health, Azure resources) is sufficient.

2. **Automated integration tests:** Not implemented in Phase 7. Manual validation using the demo walkthrough is the current acceptance criterion.

---

## Success Criteria

Phase 7 Radius validation is **complete** when:

- ✅ All Bicep files parse cleanly (`az bicep build`)
- ✅ Radius environment deploys without errors (`rad deploy` for environment)
- ✅ Application model deploys without errors (`rad deploy` for app)
- ✅ Kubernetes pods reach Running state
- ✅ Dapr components are registered in the namespace
- ✅ Azure backing resources exist in the target resource group
- ✅ `deploy-kubernetes` CI job provisions a public Radius gateway for `expense-api`, reuses `scripts/validate-deployment.sh`, and checks `notification-svc` logs with `kubectl`
- ✅ Either:
  - **Option A:** End-to-end demo validation completes ($50 auto-approve, $150 manual-review)
  - **Option B:** Live environment unavailable → validation checklist documented with clear gap explanation

**Current status:** Structural validation complete, and the Radius CI path now contains live end-to-end validation steps. Successful execution still depends on a configured live Radius environment being available to the workflow.

---

## References

- **Radius Deployment Guide:** https://docs.radapp.io/guides/deploy-apps/
- **Radius Recipes:** https://docs.radapp.io/guides/recipes/
- **Radius Environments:** https://docs.radapp.io/guides/deploy-apps/environments/
- **Phase 7 Demo Walkthrough:** [docs/phase-7-demo-walkthrough.md](./phase-7-demo-walkthrough.md)
- **ADR-0001 (Kubernetes-First Deployment Strategy):** [docs/ADR-0001-kubernetes-first-deployment.md](./ADR-0001-kubernetes-first-deployment.md)

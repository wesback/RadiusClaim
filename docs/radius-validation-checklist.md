# Kubernetes + Radius Deployment Validation Checklist

> **Purpose:** Pre-deployment validation and troubleshooting guide for Kubernetes + Radius deployment  
> **Audience:** Platform engineers deploying via `rad deploy` to Kubernetes (AKS or any K8s with Dapr and Radius)  
> **Scope:** Phase 7 validation requirements

---

## Prerequisites Validation

Before running `rad deploy`, verify these requirements are met:

### ✅ Radius Control Plane

```bash
# Verify Radius CLI is installed
rad --version
# Expected: v0.x.x or later

# Verify Radius control plane is running
kubectl get pods -n radius-system
# Expected: radius-controller-manager pods in Running state
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
# RADIUS_KUBECONFIG (raw kubeconfig content for the Kubernetes cluster with Radius)
```

**Required Variables:**
```bash
# AZURE_LOCATION (e.g., eastus, westus2) — for Azure backing services
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

---

## Deployment Steps

### Step 1: Bootstrap Radius Environment

Create a temporary bootstrap environment (required by Radius before deploying the actual environment Bicep):

```bash
rad env create bootstrap-test
rad env switch bootstrap-test
```

### Step 2: Deploy Azure Environment

```bash
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters @infra/radius/environments/azure-radius.parameters.json \
  --parameters environmentName=azure \
  --parameters kubernetesNamespace=radiusclaim-azure \
  --parameters azureProviderScope="/subscriptions/<subscription-id>/resourceGroups/<resource-group>" \
  --parameters location=<azure-location>
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

### Step 3: Deploy Application Model

```bash
rad deploy infra/radius/app.bicep \
  --parameters containerRegistry='ghcr.io/<your-org>/radiusclaim' \
  --parameters imageTag='<your-tag>' \
  --parameters deploymentTarget='radius'
```

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
```

**Validation:**
```bash
# Check Kubernetes resources were created
kubectl get pods -n radiusclaim-azure
# Expected: expense-api, workflow-engine, notification-svc pods in Running state

# Check Dapr components exist
kubectl get components -n radiusclaim-azure
# Expected: statestore, pubsub, platform-secrets components
```

---

## Post-Deployment Validation

### ✅ Pod Health

```bash
# Check all pods are Running
kubectl get pods -n radiusclaim-azure
# Expected: 3 pods with STATUS = Running

# Check pod logs for startup errors
kubectl logs -n radiusclaim-azure -l app=expense-api --tail=50
kubectl logs -n radiusclaim-azure -l app=workflow-engine --tail=50
kubectl logs -n radiusclaim-azure -l app=notification-svc --tail=50
# Expected: No error messages, Dapr sidecar initialized
```

### ✅ Dapr Component Registration

```bash
# Verify Dapr components are registered
kubectl get components -n radiusclaim-azure
# Expected: statestore, pubsub, platform-secrets

# Check component configuration
kubectl describe component statestore -n radiusclaim-azure
kubectl describe component pubsub -n radiusclaim-azure
kubectl describe component platform-secrets -n radiusclaim-azure
# Expected: Correct component type and metadata
```

### ✅ Azure Backing Resources

```bash
# Verify Storage Account for state store
az storage account list --resource-group <your-resource-group> --query "[?contains(name, 'ce')].{name:name,location:location}" -o table
# Expected: At least one storage account (created by recipe)

# Verify Service Bus namespace for pub/sub
az servicebus namespace list --resource-group <your-resource-group> --query "[].{name:name,location:location}" -o table
# Expected: Service Bus namespace (created by recipe)

# Verify Key Vault for secrets
az keyvault list --resource-group <your-resource-group> --query "[].{name:name,location:location}" -o table
# Expected: Key Vault (created by recipe)
```

### ✅ Service Connectivity

```bash
# Port-forward to expense-api
kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &
FORWARD_PID=$!

# Test health endpoint
curl http://localhost:8080/healthz
# Expected: {"status":"ok"}

# Stop port-forward
kill $FORWARD_PID
```

---

## End-to-End Validation

**IMPORTANT:** This requires a live Radius environment with deployed services. The Radius-first path does **not** depend on ACA ingress commands; use `kubectl port-forward` when the service is cluster-internal.

If a live environment is available, run the shared validation script against a port-forwarded `expense-api` service:

```bash
kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &
FORWARD_PID=$!

./scripts/validate-deployment.sh http://127.0.0.1:8080

kubectl logs -n radiusclaim-azure deployment/notification-svc -c notification-svc --tail=200
kill $FORWARD_PID
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

**Cause:** Radius requires an existing environment before deploying environment Bicep.

**Solution:**
```bash
rad env create bootstrap-temp
rad env switch bootstrap-temp
# Then retry environment deployment
```

### Issue: Pods remain in `Pending` state

**Cause:** Kubernetes cluster lacks resources or image pull fails.

**Solution:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n radiusclaim-azure
# Look for ImagePullBackOff, resource limits, or scheduling failures

# Verify images are accessible
kubectl run test-pull --image=ghcr.io/<your-org>/radiusclaim/expense-api:<tag> --command -- sleep 3600
kubectl delete pod test-pull
```

### Issue: Dapr components not registering

**Cause:** Recipe provisioning failed or Azure credentials invalid.

**Solution:**
```bash
# Check recipe execution logs
rad recipe show azure-blob-state
rad recipe show azure-servicebus-pubsub
rad recipe show azure-keyvault-secrets

# Verify Azure provider scope is correct
rad env show azure --query 'properties.providers.azure.scope'
```

### Issue: Services return 500 errors

**Cause:** Dapr sidecar not initialized or component wiring broken.

**Solution:**
```bash
# Check Dapr sidecar logs
kubectl logs -n radiusclaim-azure <pod-name> -c daprd

# Verify Dapr is enabled
kubectl get pod <pod-name> -n radiusclaim-azure -o jsonpath='{.spec.containers[*].name}'
# Expected: Container name includes "daprd"
```

---

## Known Gaps (Phase 7)

The following gaps are documented and **not considered blocking** for Phase 7 completion:

1. **Live end-to-end validation:** Requires a deployed Radius environment with reachable `expense-api` access (ingress or local `kubectl port-forward`). If unavailable, structural validation (Bicep parse, pod health, Azure resources) is sufficient.

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
- ✅ `deploy-kubernetes` CI job reuses `scripts/validate-deployment.sh` via `kubectl port-forward` and checks `notification-svc` logs with `kubectl`
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
- **ADR-0001 (Azure CLI Fallback):** [docs/ADR-0001-azure-cli-fallback.md](./ADR-0001-azure-cli-fallback.md)

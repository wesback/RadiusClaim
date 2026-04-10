---
name: "radius-idempotent-deployment"
description: "Ensure Radius environment and application deployments are repeatable without requiring cleanup between runs"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this pattern when setting up CI/CD or manual deployment workflows for Radius applications. Ensures that repeated deployments to the same environment are idempotent: they update configuration in place rather than failing due to existing resources or creating temporary artifacts.

## Problem

Early Radius examples and tutorials often show a "bootstrap environment" pattern:
```bash
rad env create bootstrap-temp-$RANDOM
rad env switch bootstrap-temp-$RANDOM
rad deploy infra/environments/production.bicep ...
rad env switch production
```

This pattern causes:
1. **Failed subsequent runs:** The target environment already exists, causing confusion or failures
2. **Orphaned bootstrap environments:** Temporary environments accumulate and are never cleaned up
3. **CI/CD complexity:** Unique bootstrap names per run (e.g., `bootstrap-${{ github.run_id }}`) waste resources

## Pattern

### For CI/CD Workflows

```bash
# In GitHub Actions or similar CI/CD
export RADIUS_ENVIRONMENT_NAME="production"  # Or azure, staging, etc.

# Create environment if it doesn't exist (idempotent)
rad env create "$RADIUS_ENVIRONMENT_NAME" || true
rad env switch "$RADIUS_ENVIRONMENT_NAME"

# Deploy environment Bicep (updates in place)
rad deploy infra/radius/environments/production.bicep \
  --parameters environmentName="$RADIUS_ENVIRONMENT_NAME" \
  --parameters ... (other params)

# No explicit rad env switch needed - rad deploy switches automatically

# Deploy application (uses current environment)
rad deploy infra/radius/app.bicep --parameters ...
```

### For Manual/Local Deployment

```bash
# Create or reuse existing environment
rad env create azure || true
rad env switch azure

# Deploy environment configuration
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters environmentName=azure \
  --parameters azureProviderScope="/subscriptions/.../resourceGroups/..." \
  --parameters location=eastus

# Deploy application
rad deploy infra/radius/app.bicep
```

## Key Principles

1. **Use stable environment names:** `production`, `azure`, `staging` — not `bootstrap-$RANDOM` or `temp-env-123`
2. **Idempotent creation:** `rad env create <name> || true` succeeds whether the environment exists or not
3. **Deploy updates in place:** `rad deploy` on an environment Bicep updates the environment's configuration
4. **No explicit post-deploy switch:** `rad deploy` automatically switches to the deployed environment

## Workflow Integration

### GitHub Actions Example

```yaml
env:
  RADIUS_ENVIRONMENT_NAME: azure
  # No RADIUS_BOOTSTRAP_ENVIRONMENT variable needed

steps:
  - name: Configure Radius workspace
    run: |
      rad workspace create kubernetes "$WORKSPACE_NAME"
      rad group create "$GROUP_NAME"
      
      # Create or switch to target environment (idempotent)
      rad env create "$RADIUS_ENVIRONMENT_NAME" || true
      rad env switch "$RADIUS_ENVIRONMENT_NAME"

  - name: Deploy Azure-backed Radius environment (idempotent)
    run: |
      rad deploy infra/radius/environments/azure-radius.bicep \
        --parameters environmentName="$RADIUS_ENVIRONMENT_NAME" \
        --parameters kubernetesNamespace="$KUBERNETES_NAMESPACE" \
        --parameters azureProviderScope="$AZURE_PROVIDER_SCOPE" \
        --parameters location="$AZURE_LOCATION"

  - name: Deploy application
    run: |
      rad deploy infra/radius/app.bicep \
        --parameters containerRegistry="$CONTAINER_REGISTRY" \
        --parameters imageTag="$IMAGE_TAG"
```

## Documentation Pattern

When documenting deployment procedures:

**Good:**
```markdown
Create or switch to the target environment:
\`\`\`bash
rad env create azure || true
rad env switch azure
\`\`\`
```

**Bad:**
```markdown
Create a bootstrap environment first:
\`\`\`bash
rad env create bootstrap-temp
rad env switch bootstrap-temp
# Then deploy the real environment...
\`\`\`
```

## Namespace Collision Guard

Radius enforces that two environments cannot share a Kubernetes namespace. If a prior run created an environment under a different name (e.g. the `environmentName` parameter defaulted to `radiusclaim-azure` instead of `azure`), that stale environment squats on the namespace and blocks all subsequent deploys with HTTP 409 Conflict:

> "Environment /…/environments/radiusclaim-azure with the same namespace (radiusclaim-azure) already exists"

This is **distinct** from the stuck-state Conflict ("in progress state"). It requires proactive cleanup before the `rad deploy`.

### Pattern

```bash
# Before rad deploy — clear any stale environment squatting on the target namespace.
if [ "$DRY_RUN" != true ]; then
  _stale_env="$("$RAD_BIN" env list -o json 2>/dev/null \
    | sed -n '/^\[/,$p' \
    | jq -r --arg ns "${KUBERNETES_NAMESPACE}" --arg target "${ENV_NAME}" \
        '.[] | select(.properties.compute.namespace == $ns and .name != $target) | .name' \
        2>/dev/null \
    || true)"
  if [ -n "$_stale_env" ]; then
    log_warning "Stale Radius environment '${_stale_env}' owns namespace '${KUBERNETES_NAMESPACE}' — removing to allow idempotent redeploy."
    "$RAD_BIN" env delete "${_stale_env}" --yes 2>/dev/null || true
    log_info "Stale environment '${_stale_env}' removed."
  fi
  unset _stale_env
fi
```

### When This Fires

- Environment was created with a different `environmentName` parameter (e.g. old default was `radiusclaim-azure`, new canonical name is `azure`).
- Manual `rad env create <name>` was called with a different name before the bootstrap ran.
- A failed/aborted run left an environment in a partially-created state under a legacy name.

## Stale Application Guard

Radius also enforces that an application resource cannot be re-deployed if it already exists bound to a **different environment**. If a prior run created the `radiusclaim` application inside the old `radiusclaim-azure` environment, a new deploy targeting `azure` fails with HTTP 400 BadRequest:

> "Attempted to deploy existing resource 'radiusclaim' which has a different application and/or environment."

This is **distinct** from the namespace-collision and stuck-state errors. It requires deleting the stale application resource before deploying.

**This same error also applies to Dapr component resources** (Applications.Dapr/secretStores, Applications.Dapr/stateStores, Applications.Dapr/pubSubBrokers). These resources can also become bound to a stale environment and must be cleaned up before deploying.

### Pattern

```bash
# Before rad deploy app.bicep — clear any stale application bound to a different environment.
# Use `rad resource list Applications.Core/applications` (not `rad app list`) for reliable detection.
if [ "$DRY_RUN" != true ]; then
  _target_env_id="/planes/radius/local/resourcegroups/${GROUP_NAME}/providers/Applications.Core/environments/${ENV_NAME}"
  _app_json="$("$RAD_BIN" resource list Applications.Core/applications \
    -g "$GROUP_NAME" -w "$WORKSPACE_NAME" -o json 2>/dev/null || true)"
  
  # Extract valid JSON (rad CLI sometimes prefixes non-JSON output).
  _app_json="$(echo "$_app_json" | sed -n '/^\[/,$p')"
  
  if [ -n "$_app_json" ] && echo "$_app_json" | jq empty 2>/dev/null; then
    _stale_app="$(echo "$_app_json" \
      | jq -r --arg name "${APP_NAME}" --arg env "${_target_env_id}" \
          '.[] | select(.name == $name) | select(.properties.environment != null) | select((.properties.environment | ascii_downcase) != ($env | ascii_downcase)) | .name' \
          2>/dev/null \
      || true)"
    if [ -n "$_stale_app" ]; then
      log_warning "Application '${_stale_app}' is bound to a different environment — removing to allow idempotent redeploy."
      "$RAD_BIN" app delete "${_stale_app}" \
        -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      # Belt-and-suspenders: rad resource delete uses TWO positional args (type name).
      "$RAD_BIN" resource delete Applications.Core/applications "${_stale_app}" \
        -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      log_info "Stale application '${_stale_app}' removed."
    fi
  fi
  unset _stale_app _target_env_id _app_json
fi

# Also check Dapr component resources (secretStores, stateStores, pubSubBrokers).
# These follow the same pattern — list, detect environment mismatch, delete.
if [ "$DRY_RUN" != true ]; then
  _target_env_id="/planes/radius/local/resourcegroups/${GROUP_NAME}/providers/Applications.Core/environments/${ENV_NAME}"
  
  # Check secretStores
  _secret_json="$("$RAD_BIN" resource list Applications.Dapr/secretStores \
    -g "$GROUP_NAME" -w "$WORKSPACE_NAME" -o json 2>/dev/null || true)"
  _secret_json="$(echo "$_secret_json" | sed -n '/^\[/,$p')"
  if [ -n "$_secret_json" ] && echo "$_secret_json" | jq empty 2>/dev/null; then
    _stale_secrets="$(echo "$_secret_json" \
      | jq -r --arg env "${_target_env_id}" \
          '.[] | select(.properties.environment != null) | select((.properties.environment | ascii_downcase) != ($env | ascii_downcase)) | .name' \
          2>/dev/null \
      || true)"
    if [ -n "$_stale_secrets" ]; then
      while IFS= read -r _secret_name; do
        [ -n "$_secret_name" ] || continue
        "$RAD_BIN" resource delete Applications.Dapr/secretStores "${_secret_name}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      done <<< "$_stale_secrets"
    fi
  fi
  
  # Check stateStores (same pattern)
  _state_json="$("$RAD_BIN" resource list Applications.Dapr/stateStores \
    -g "$GROUP_NAME" -w "$WORKSPACE_NAME" -o json 2>/dev/null || true)"
  _state_json="$(echo "$_state_json" | sed -n '/^\[/,$p')"
  if [ -n "$_state_json" ] && echo "$_state_json" | jq empty 2>/dev/null; then
    _stale_states="$(echo "$_state_json" \
      | jq -r --arg env "${_target_env_id}" \
          '.[] | select(.properties.environment != null) | select((.properties.environment | ascii_downcase) != ($env | ascii_downcase)) | .name' \
          2>/dev/null \
      || true)"
    if [ -n "$_stale_states" ]; then
      while IFS= read -r _state_name; do
        [ -n "$_state_name" ] || continue
        "$RAD_BIN" resource delete Applications.Dapr/stateStores "${_state_name}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      done <<< "$_stale_states"
    fi
  fi
  
  # Check pubSubBrokers (same pattern)
  _pubsub_json="$("$RAD_BIN" resource list Applications.Dapr/pubSubBrokers \
    -g "$GROUP_NAME" -w "$WORKSPACE_NAME" -o json 2>/dev/null || true)"
  _pubsub_json="$(echo "$_pubsub_json" | sed -n '/^\[/,$p')"
  if [ -n "$_pubsub_json" ] && echo "$_pubsub_json" | jq empty 2>/dev/null; then
    _stale_pubsubs="$(echo "$_pubsub_json" \
      | jq -r --arg env "${_target_env_id}" \
          '.[] | select(.properties.environment != null) | select((.properties.environment | ascii_downcase) != ($env | ascii_downcase)) | .name' \
          2>/dev/null \
      || true)"
    if [ -n "$_stale_pubsubs" ]; then
      while IFS= read -r _pubsub_name; do
        [ -n "$_pubsub_name" ] || continue
        "$RAD_BIN" resource delete Applications.Dapr/pubSubBrokers "${_pubsub_name}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      done <<< "$_stale_pubsubs"
    fi
  fi
  
  unset _target_env_id _secret_json _stale_secrets _state_json _stale_states _pubsub_json _stale_pubsubs
fi
```

**Key differences from `rad app list`:**
- `rad resource list Applications.Core/applications` queries the resource plane directly and surfaces apps in all states, including orphaned/broken
- Use case-insensitive comparison (`ascii_downcase`) for Radius resource IDs to handle mixed-case paths
- Delete via `rad resource delete Applications.Core/applications "{name}"` — **two separate positional arguments** (type, then name), NOT a single combined path like `Applications.Core/applications/{name}`
- `rad app delete` is unreliable for programmatic use — it may exit 0 without actually removing the resource

**Dapr component resource types:**
- `Applications.Dapr/secretStores` — Dapr secret store components
- `Applications.Dapr/stateStores` — Dapr state store components  
- `Applications.Dapr/pubSubBrokers` — Dapr pub/sub broker components
- All use the same two-arg deletion syntax: `rad resource delete Applications.Dapr/secretStores "{name}"`
- All must be checked for environment mismatches and cleaned up BEFORE the application deploy

### When This Fires

- Application was previously deployed to a different environment (e.g. `radiusclaim-azure`); bootstrap now targets `azure`.
- A failed/aborted run left an application resource associated with a now-deleted or renamed environment.
- AKS cluster was reused without clearing Radius control plane state.
- **Dapr components (secretStores, stateStores, pubSubBrokers) were deployed with the old environment binding and are now stale.**

## Validation

After implementing this pattern:
- [ ] Workflow can run multiple times without cleanup
- [ ] No orphaned bootstrap environments accumulate
- [ ] Environment names are stable and predictable
- [ ] CI/CD logs show `|| true` handling gracefully when environment exists
- [ ] Documentation reflects idempotent pattern

## Examples

- GitHub Actions workflow: `.github/workflows/deploy-azure.yml`
- Manual deployment guide: `docs/end-to-end-setup-walkthrough.md`
- Validation checklist: `docs/radius-validation-checklist.md`

## Radius Control Plane State Corruption Recovery

When direct kubectl deletion of Radius-managed CRDs (or other control-plane state corruption) leaves orphaned references in Radius's internal database, `rad resource delete` commands and normal cleanup guards fail to resolve the issue. Symptoms include:

- `rad resource delete` fails with "resource not found" but Radius still believes the resource exists
- Deployment errors persist even after manually deleting Kubernetes CRDs
- Environment mismatch errors for resources that no longer exist in the cluster
- Stale application/component references that cannot be removed via Radius CLI

### Recovery: Full Radius Reinstall

The **only reliable recovery** is to completely reinstall Radius to wipe the control plane state:

```bash
# Step 1: Uninstall Radius (wipes control plane state)
rad uninstall kubernetes

# Step 2: Reinstall Radius (clean state)
rad install kubernetes

# Step 3: Verify Radius pods are running
kubectl get pods -n radius-system

# Step 4: Re-run bootstrap.sh to recreate the environment
./scripts/bootstrap.sh --resource-group <your-resource-group> --yes
```

### Why This Works

- `rad uninstall kubernetes` removes the Radius control plane entirely, including all internal state/database
- `rad install kubernetes` creates a fresh control plane with no prior history
- bootstrap.sh recreates the workspace, group, environment, and application from scratch
- All orphaned references are gone because the control plane state is wiped

### When to Use This Recovery

- Direct `kubectl delete` of Dapr component CRDs left orphaned Radius state
- `rad resource delete` fails but resources still appear in `rad resource list`
- Environment mismatch errors persist after all cleanup attempts
- Stale application/component references that cannot be removed
- **When normal cleanup guards and `rad resource delete` commands have failed**

### What You Lose

- All Radius control plane history (environments, applications, resources)
- Existing workspace/group/environment configuration (must recreate)
- **Does NOT affect**: Running Kubernetes workloads, Azure resources, or application data

### After Reinstall

You must re-run the full bootstrap sequence:
1. `rad workspace create` and `rad group create`
2. Deploy the Radius environment via `rad deploy infra/radius/environments/azure-radius.bicep`
3. Deploy the application via `rad deploy infra/radius/app.bicep`

Or simply re-run `./scripts/bootstrap.sh --resource-group <name> --yes` which handles all of the above.

## Related Patterns

- **radius-namespace-migration:** When preserving environment identity across resource type migrations
- **kubernetes-first-radius-azure:** When deploying Radius to Kubernetes with Azure backing services

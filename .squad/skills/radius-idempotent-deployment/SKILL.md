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

## Related Patterns

- **radius-namespace-migration:** When preserving environment identity across resource type migrations
- **kubernetes-first-radius-azure:** When deploying Radius to Kubernetes with Azure backing services

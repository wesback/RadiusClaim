# Workload Identity Migration to Bicep

## Summary

Workload identity setup has been moved from bash scripts to Infrastructure as Code (Bicep).

## What Changed

### New Infrastructure

**Created:** `infra/azure/workload-identity.bicep`
- Provisions user-assigned managed identity
- Creates federated identity credentials for service accounts (expense-api, workflow-engine, notification-svc)
- Outputs client ID and principal ID for use in Radius deployment

**Updated:** `scripts/bootstrap.sh`
- Added Bicep deployment step after AKS OIDC/workload identity enablement
- Captures OIDC issuer URL from AKS cluster
- Deploys workload-identity.bicep with issuer URL as parameter
- Captures managed identity outputs and passes to Radius deployment

## What Can Be Deleted

The following sections in `scripts/deploy-dapr-components-workload-identity.sh` are now **redundant** and can be removed:

### 1. OIDC Issuer Retrieval (Lines ~209-216)
```bash
OIDC_ISSUER=$(echo "$CLUSTER_JSON" | jq -r '.oidcIssuerProfile.issuerUrl // empty')
if [[ -z "$OIDC_ISSUER" ]]; then
  echo "Error: Could not retrieve OIDC issuer URL from cluster"
  exit 4
fi
echo "  OIDC Issuer URL:   $OIDC_ISSUER"
```
**Reason:** Bootstrap.sh now fetches the OIDC issuer URL before calling the Bicep template.

### 2. Managed Identity Creation (Lines ~218-250)
```bash
echo "→ Setting up managed identity for workload..."

IDENTITY_JSON=$(az identity show -g "$RESOURCE_GROUP" -n "$MANAGED_IDENTITY_NAME" -o json 2>/dev/null || echo "{}")

if [[ $(echo "$IDENTITY_JSON" | jq -r '.id // empty') == "" ]]; then
  echo "  → Creating user-assigned managed identity..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would create identity: $MANAGED_IDENTITY_NAME"
    ...
  else
    IDENTITY_JSON=$(az identity create -g "$RESOURCE_GROUP" -n "$MANAGED_IDENTITY_NAME" -o json)
    echo "  ✓ Managed identity created"
  fi
else
  echo "  ✓ Managed identity already exists"
fi

MANAGED_IDENTITY_CLIENT_ID=$(echo "$IDENTITY_JSON" | jq -r '.clientId // empty')
MANAGED_IDENTITY_OBJECT_ID=$(echo "$IDENTITY_JSON" | jq -r '.principalId // empty')
```
**Reason:** Bicep template creates the managed identity idempotently.

### 3. Federated Credential Creation (Lines ~440-473)
```bash
# Create federated identity credentials
for SA_NAME in "${SERVICE_ACCOUNTS[@]}"; do
  FED_CRED_NAME="$SA_NAME"
  FED_SUBJECT="system:serviceaccount:${NAMESPACE}:${SA_NAME}"
  
  echo "  → Checking federated credential: $FED_CRED_NAME"
  
  FED_EXISTS=$(az identity federated-credential list \
    --identity-name "$MANAGED_IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$FED_CRED_NAME'].name | [0]" \
    -o tsv 2>/dev/null || echo "")
  
  if [[ -z "$FED_EXISTS" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "    [DRY RUN] Would create federated credential: $FED_CRED_NAME"
    else
      az identity federated-credential create \
        --name "$FED_CRED_NAME" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "$OIDC_ISSUER" \
        --subject "$FED_SUBJECT" \
        --audience "api://AzureADTokenExchange" \
        --output none 2>/dev/null || echo "    ⚠ Federated credential may already exist"
      echo "    ✓ Federated credential created"
    fi
  else
    echo "    ✓ Federated credential already exists"
  fi
  
  # Create/annotate Kubernetes service account
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "    [DRY RUN] Would annotate service account with azure.workload.identity/client-id"
  else
    kubectl create serviceaccount "$SA_NAME" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl annotate serviceaccount "$SA_NAME" \
      -n "$NAMESPACE" \
      azure.workload.identity/client-id="$MANAGED_IDENTITY_CLIENT_ID" \
      --overwrite >/dev/null 2>&1
    echo "    ✓ Service account annotated"
  fi
done
```
**Reason:** Bicep template creates all federated credentials in a loop. Service account annotation still needed (kept in script).

### 4. RBAC Role Assignments (Lines ~347-419)
The role assignments for Storage, Key Vault, and Service Bus should **remain in the script** temporarily, but will eventually move to Radius recipes (per Graham's task in the backlog).

**Keep for now:**
- Storage Blob Data Contributor assignment
- Key Vault Secrets User assignment
- Azure Service Bus Data Owner assignment

These will be moved to individual recipes (state-store.bicep, secrets.bicep, pubsub.bicep) as part of a separate task.

## What Remains in the Script

The script should now focus on:
1. **Service account annotation** — Kubernetes-side wiring (federated credentials are in Bicep, but k8s annotation is runtime)
2. **RBAC role assignments** — Temporary; will move to recipes later
3. **Dapr component CRD validation** — Ensuring components are present (though Radius now projects these automatically)

## How to Get AKS OIDC Issuer URL

If you need the OIDC issuer URL manually (e.g., for debugging):

```bash
az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query oidcIssuerProfile.issuerUrl \
  -o tsv
```

Example output:
```
https://eastus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/12345678-1234-1234-1234-123456789abc/
```

## Phase 3 Completion: Zero Bootstrap Compensation

**Date:** 2026-03-28

All workload identity setup is now **fully in Bicep.** Bootstrap no longer needs to compensate for missing infrastructure declarations.

### What Changed in Phase 3

1. **Workload identity federation is declarative:**
   - `infra/azure/workload-identity.bicep` creates managed identity + federated credentials
   - Environment Bicep passes identity IDs to recipes as parameters
   - Recipes use those IDs in Component metadata

2. **No bootstrap workarounds needed:**
   - ✅ Managed identity creation moved to workload-identity.bicep
   - ✅ Federated credential creation moved to workload-identity.bicep
   - ✅ Service account annotation moved to Kubernetes manifests (no bootstrap patching)
   - ✅ RBAC assignments declared inline in recipes

3. **Result:** Bootstrap is pure orchestration
   - Enable OIDC + workload identity addon
   - Deploy workload-identity.bicep
   - Deploy Radius environment (recipes handle all wiring)
   - Deploy application
   - Validate

### Idempotency Verification

The fully-declarative approach is idempotent:
- Re-running workload-identity.bicep does not create duplicate resources
- Federated credentials are created declaratively (Azure handles conflicts)
- Managed identity properties are updated (not replaced) if changed

**To verify:**
```bash
# Run deployment twice — second should report "No changes detected"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/azure/workload-identity.bicep \
  --parameters oidcIssuerUrl="$OIDC_ISSUER"
```

### See Also

For full Phase 3 validation steps, see: `PHASE3_INTEGRATION_VALIDATION.md`

---

## Integration with Bootstrap

Bootstrap.sh now:
1. Enables OIDC issuer + workload identity addon on AKS
2. Fetches OIDC issuer URL from the cluster
3. Deploys `infra/azure/workload-identity.bicep` with the issuer URL
4. Captures managed identity client ID and principal ID from Bicep outputs
5. Passes these IDs to `rad deploy` as parameters
6. Recipes use these IDs in Component metadata (no bootstrap compensation)

The managed identity is created **before** Radius deployment, so recipes can immediately use the principal ID for RBAC assignments.

## Idempotency

The Bicep template is fully idempotent:
- Re-running the deployment does not create duplicate resources
- Federated credentials are created declaratively (Azure handles conflicts)
- Managed identity properties are updated if changed

## Next Steps (Out of Scope for This Task)

1. **Move RBAC to recipes** — Role assignments should live in state-store.bicep, secrets.bicep, pubsub.bicep (Graham's task)
2. **Simplify deploy-dapr-components script** — Once RBAC moves to recipes, most of this script can be deleted
3. **Consider moving service account annotation to Bicep** — Possible with Azure CLI Deployment Scripts or Kubernetes provider

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/platform-common.sh"

# deploy-dapr-components-workload-identity.sh with Workload Identity support
#
# Automates the deployment of Dapr Component objects with Azure Workload Identity.
# This is the clean, long-term solution that replaces service-principal-with-client-secret auth.
#
# Usage:
#   ./scripts/deploy-dapr-components.sh [OPTIONS]
#
# Options:
#   --app-name <name>          Radius application name (default: radiusclaim)
#   --env-name <name>          Radius environment name (default: azure)
#   --resource-group <name>    Azure resource group (required)
#   --cluster-name <name>      AKS cluster name (default: radiusclaim-aks)
#   --namespace <name>         Kubernetes namespace override (auto-detected if not provided)
#   --auth-mode <mode>         Authentication mode: workload-identity or service-principal (default: workload-identity)
#   --setup-workload-identity  Enable and configure workload identity on the cluster
#   --dry-run                  Generate component YAMLs without applying
#   --help                     Show this help message
#
# Prerequisites:
#   - rad CLI (Radius application must be deployed)
#   - kubectl (Kubernetes cluster access)
#   - az CLI (Azure credentials configured)
#   - jq (JSON processor)
#
# Workload Identity Mode (default):
#   - No AZURE_CLIENT_SECRET needed
#   - Requires AKS with OIDC issuer and workload identity addon enabled
#   - Creates federated identity credentials automatically
#   - Grants RBAC on Azure resources
#
# Service Principal Mode (fallback):
#   - Requires: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID
#   - Uses traditional client secret auth
#
# Exit codes:
#   0 - Success
#   1 - Missing prerequisites
#   2 - Missing required parameters
#   3 - Radius resource not found
#   4 - Azure auth/resource lookup failed
#   5 - Kubernetes deployment failed

APP_NAME="radiusclaim"
ENV_NAME="azure"
RESOURCE_GROUP=""
CLUSTER_NAME="radiusclaim-aks"
NAMESPACE=""
AUTH_MODE="workload-identity"
SETUP_WORKLOAD_IDENTITY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --env-name)
      ENV_NAME="$2"
      shift 2
      ;;
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --auth-mode)
      AUTH_MODE="$2"
      shift 2
      ;;
    --setup-workload-identity)
      SETUP_WORKLOAD_IDENTITY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      log_error "Unknown option $1"
      exit 2
      ;;
  esac
done

command -v rad >/dev/null 2>&1 || { log_error "rad CLI not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl not found"; exit 1; }
command -v az >/dev/null 2>&1 || { log_error "az CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }

if [[ -z "$RESOURCE_GROUP" ]]; then
  log_error "--resource-group is required"
  exit 2
fi

if [[ "$AUTH_MODE" != "workload-identity" && "$AUTH_MODE" != "service-principal" ]]; then
  log_error "--auth-mode must be 'workload-identity' or 'service-principal'"
  exit 2
fi

if [[ -z "$NAMESPACE" ]]; then
  ENV_JSON=$(rad env show "$ENV_NAME" -o json 2>/dev/null || echo "{}")
  ENV_NAMESPACE=$(echo "$ENV_JSON" | jq -r '.properties.compute.namespace // empty')

  if [[ -z "$ENV_NAMESPACE" ]]; then
    log_error "Could not auto-detect namespace. Please provide --namespace"
    exit 3
  fi

  NAMESPACE="${ENV_NAMESPACE}-${APP_NAME}"
fi

AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")
AZURE_TENANT_ID="${AZURE_TENANT_ID:-$(az account show --query tenantId -o tsv 2>/dev/null || echo "")}"

if [[ -z "$AZURE_SUBSCRIPTION_ID" || -z "$AZURE_TENANT_ID" ]]; then
  log_error "Could not determine Azure subscription or tenant ID"
  exit 4
fi

echo "=========================================="
echo "Deploying Dapr Components with Workload Identity"
echo "=========================================="
echo "Application:     $APP_NAME"
echo "Environment:     $ENV_NAME"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Cluster:         $CLUSTER_NAME"
echo "Namespace:       $NAMESPACE"
echo "Auth Mode:       $AUTH_MODE"
echo "Subscription:    $AZURE_SUBSCRIPTION_ID"
echo "Tenant:          $AZURE_TENANT_ID"
echo "Dry Run:         $DRY_RUN"
echo ""

# Step 1: Check and enable workload identity prerequisites if requested
if [[ "$AUTH_MODE" == "workload-identity" ]]; then
  echo "→ Checking workload identity prerequisites..."
  
  CLUSTER_JSON=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" -o json 2>/dev/null || echo "{}")
  OIDC_ENABLED=$(echo "$CLUSTER_JSON" | jq -r '.oidcIssuerProfile.enabled // false')
  WI_ENABLED=$(echo "$CLUSTER_JSON" | jq -r '.securityProfile.workloadIdentity.enabled // false')
  
  echo "  OIDC Issuer:       $OIDC_ENABLED"
  echo "  Workload Identity: $WI_ENABLED"
  
  if [[ "$OIDC_ENABLED" != "true" || "$WI_ENABLED" != "true" ]]; then
    if [[ "$SETUP_WORKLOAD_IDENTITY" == "true" ]]; then
      echo ""
      echo "  → Enabling OIDC issuer and workload identity on cluster..."
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would run: az aks update -g $RESOURCE_GROUP -n $CLUSTER_NAME --enable-oidc-issuer --enable-workload-identity"
      else
        az aks update -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" \
          --enable-oidc-issuer --enable-workload-identity \
          --output none
        echo "  ✓ Workload identity enabled on cluster"
        
        # Refresh cluster info
        CLUSTER_JSON=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" -o json 2>/dev/null || echo "{}")
      fi
    else
      echo ""
      echo "Error: Workload identity requires OIDC issuer and workload identity addon to be enabled"
      echo "  Run with --setup-workload-identity to enable automatically, or enable manually:"
      echo "  az aks update -g $RESOURCE_GROUP -n $CLUSTER_NAME --enable-oidc-issuer --enable-workload-identity"
      echo ""
      echo "  Alternatively, use --auth-mode service-principal with AZURE_CLIENT_SECRET"
      exit 4
    fi
  else
    echo "  ✓ Workload identity prerequisites met"
  fi
  
  OIDC_ISSUER=$(echo "$CLUSTER_JSON" | jq -r '.oidcIssuerProfile.issuerUrl // empty')
  if [[ -z "$OIDC_ISSUER" ]]; then
    echo "Error: Could not retrieve OIDC issuer URL from cluster"
    exit 4
  fi
  echo "  OIDC Issuer URL:   $OIDC_ISSUER"
  echo ""
fi

# Step 2: Create or retrieve managed identity for workload
MANAGED_IDENTITY_NAME="radiusclaim-workload-identity"

if [[ "$AUTH_MODE" == "workload-identity" ]]; then
  echo "→ Setting up managed identity for workload..."
  
  IDENTITY_JSON=$(az identity show -g "$RESOURCE_GROUP" -n "$MANAGED_IDENTITY_NAME" -o json 2>/dev/null || echo "{}")
  
  if [[ $(echo "$IDENTITY_JSON" | jq -r '.id // empty') == "" ]]; then
    echo "  → Creating user-assigned managed identity..."
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [DRY RUN] Would create identity: $MANAGED_IDENTITY_NAME"
      MANAGED_IDENTITY_CLIENT_ID="00000000-0000-0000-0000-000000000000"
      MANAGED_IDENTITY_OBJECT_ID="00000000-0000-0000-0000-000000000000"
    else
      IDENTITY_JSON=$(az identity create -g "$RESOURCE_GROUP" -n "$MANAGED_IDENTITY_NAME" -o json)
      echo "  ✓ Managed identity created"
    fi
  else
    echo "  ✓ Managed identity already exists"
  fi
  
  MANAGED_IDENTITY_CLIENT_ID=$(echo "$IDENTITY_JSON" | jq -r '.clientId // empty')
  MANAGED_IDENTITY_OBJECT_ID=$(echo "$IDENTITY_JSON" | jq -r '.principalId // empty')
  
  if [[ -z "$MANAGED_IDENTITY_CLIENT_ID" || -z "$MANAGED_IDENTITY_OBJECT_ID" ]]; then
    echo "Error: Could not retrieve managed identity details"
    exit 4
  fi
  
  echo "  Client ID:  $MANAGED_IDENTITY_CLIENT_ID"
  echo "  Object ID:  $MANAGED_IDENTITY_OBJECT_ID"
  echo ""
  
  # Use managed identity for auth
  AZURE_CLIENT_ID_VALUE="$MANAGED_IDENTITY_CLIENT_ID"
  AZURE_PRINCIPAL_ID_VALUE="$MANAGED_IDENTITY_OBJECT_ID"
else
  # Service principal mode
  AZURE_CLIENT_ID_VALUE="${AZURE_CLIENT_ID:-}"
  AZURE_CLIENT_SECRET_VALUE="${AZURE_CLIENT_SECRET:-}"
  AZURE_PRINCIPAL_ID_VALUE="${AZURE_PRINCIPAL_ID:-}"
  
  if [[ -z "$AZURE_CLIENT_ID_VALUE" ]] || [[ -z "$AZURE_CLIENT_SECRET_VALUE" ]]; then
    echo "Error: Service principal mode requires AZURE_CLIENT_ID and AZURE_CLIENT_SECRET"
    exit 4
  fi
  
  if [[ -z "$AZURE_PRINCIPAL_ID_VALUE" ]]; then
    AZURE_PRINCIPAL_ID_VALUE=$(az ad sp show --id "$AZURE_CLIENT_ID_VALUE" --query id -o tsv 2>/dev/null || echo "")
  fi
  
  if [[ -z "$AZURE_PRINCIPAL_ID_VALUE" ]]; then
    echo "Error: Could not resolve principal object ID"
    exit 4
  fi
  
  echo "  Using service principal: $AZURE_CLIENT_ID_VALUE"
  echo ""
fi

# Step 3: Fetch Radius resource details
echo "→ Fetching Radius resource details..."
STATESTORE_JSON=$(rad resource show Applications.Dapr/stateStores statestore -a "$APP_NAME" -o json 2>/dev/null || echo "{}")
PUBSUB_JSON=$(rad resource show Applications.Dapr/pubSubBrokers pubsub -a "$APP_NAME" -o json 2>/dev/null || echo "{}")
SECRETS_JSON=$(rad resource show Applications.Dapr/secretStores platform-secrets -a "$APP_NAME" -o json 2>/dev/null || echo "{}")

STORAGE_ACCOUNT=$(echo "$STATESTORE_JSON" | jq -r '.properties.recipe.parameters.storageAccountName // empty')
CONTAINER_NAME=$(echo "$STATESTORE_JSON" | jq -r '.properties.recipe.parameters.containerName // empty')
SERVICEBUS_NAMESPACE=$(echo "$PUBSUB_JSON" | jq -r '.properties.recipe.parameters.namespaceName // empty')
VAULT_NAME=$(echo "$SECRETS_JSON" | jq -r '.properties.recipe.parameters.vaultName // empty')

if [[ -z "$STORAGE_ACCOUNT" ]] || [[ -z "$CONTAINER_NAME" ]] || [[ -z "$SERVICEBUS_NAMESPACE" ]] || [[ -z "$VAULT_NAME" ]]; then
  echo "Error: Failed to retrieve recipe parameters from Radius"
  echo "  Storage Account: ${STORAGE_ACCOUNT:-NOT FOUND}"
  echo "  Container Name:  ${CONTAINER_NAME:-NOT FOUND}"
  echo "  Service Bus:     ${SERVICEBUS_NAMESPACE:-NOT FOUND}"
  echo "  Key Vault:       ${VAULT_NAME:-NOT FOUND}"
  exit 3
fi

echo "  ✓ State Store:  $STORAGE_ACCOUNT / $CONTAINER_NAME"
echo "  ✓ Pub/Sub:      $SERVICEBUS_NAMESPACE"
echo "  ✓ Secret Store: $VAULT_NAME"
echo ""

# Step 4: Get Azure resource IDs
echo "→ Retrieving Azure resource IDs..."
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  -o tsv 2>/dev/null || echo "")
KEYVAULT_ID=$(az keyvault show \
  --name "$VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  -o tsv 2>/dev/null || echo "")
SERVICEBUS_ID=$(az servicebus namespace show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SERVICEBUS_NAMESPACE" \
  --query id \
  -o tsv 2>/dev/null || echo "")

# Only get connection string if in service-principal mode
if [[ "$AUTH_MODE" == "service-principal" ]]; then
  SERVICEBUS_CONN=$(az servicebus namespace authorization-rule keys list \
    --resource-group "$RESOURCE_GROUP" \
    --namespace-name "$SERVICEBUS_NAMESPACE" \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString \
    -o tsv 2>/dev/null || echo "")
  
  if [[ -z "$STORAGE_ACCOUNT_ID" ]] || [[ -z "$KEYVAULT_ID" ]] || [[ -z "$SERVICEBUS_CONN" ]]; then
    echo "Error: Failed to retrieve required Azure resource details"
    exit 4
  fi
else
  if [[ -z "$STORAGE_ACCOUNT_ID" ]] || [[ -z "$KEYVAULT_ID" ]] || [[ -z "$SERVICEBUS_ID" ]]; then
    echo "Error: Failed to retrieve required Azure resource details"
    exit 4
  fi
fi
echo "  ✓ Resource IDs retrieved"
echo ""

# Step 5: Grant RBAC on Azure resources
echo "→ Granting RBAC permissions..."

STORAGE_ROLE_ASSIGNMENT_COUNT=$(az role assignment list \
  --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ACCOUNT_ID" \
  --query 'length(@)' \
  -o tsv 2>/dev/null || echo "0")

if [[ "$STORAGE_ROLE_ASSIGNMENT_COUNT" == "0" ]]; then
  echo "  → Granting Storage Blob Data Contributor..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would grant Storage Blob Data Contributor on $STORAGE_ACCOUNT"
  else
    az role assignment create \
      --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "$STORAGE_ACCOUNT_ID" \
      --output none
    echo "  ✓ Storage Blob Data Contributor granted"
  fi
else
  echo "  ✓ Storage Blob Data Contributor already granted"
fi

KEYVAULT_ROLE_ASSIGNMENT_COUNT=$(az role assignment list \
  --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
  --role "Key Vault Secrets User" \
  --scope "$KEYVAULT_ID" \
  --query 'length(@)' \
  -o tsv 2>/dev/null || echo "0")

if [[ "$KEYVAULT_ROLE_ASSIGNMENT_COUNT" == "0" ]]; then
  echo "  → Granting Key Vault Secrets User..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would grant Key Vault Secrets User on $VAULT_NAME"
  else
    az role assignment create \
      --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
      --assignee-principal-type ServicePrincipal \
      --role "Key Vault Secrets User" \
      --scope "$KEYVAULT_ID" \
      --output none
    echo "  ✓ Key Vault Secrets User granted"
  fi
else
  echo "  ✓ Key Vault Secrets User already granted"
fi

# Grant Service Bus Data Owner role (needed for workload identity mode)
if [[ "$AUTH_MODE" == "workload-identity" ]]; then
  SERVICEBUS_ROLE_ASSIGNMENT_COUNT=$(az role assignment list \
    --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
    --role "Azure Service Bus Data Owner" \
    --scope "$SERVICEBUS_ID" \
    --query 'length(@)' \
    -o tsv 2>/dev/null || echo "0")
  
  if [[ "$SERVICEBUS_ROLE_ASSIGNMENT_COUNT" == "0" ]]; then
    echo "  → Granting Azure Service Bus Data Owner..."
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [DRY RUN] Would grant Azure Service Bus Data Owner on $SERVICEBUS_NAMESPACE"
    else
      az role assignment create \
        --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
        --assignee-principal-type ServicePrincipal \
        --role "Azure Service Bus Data Owner" \
        --scope "$SERVICEBUS_ID" \
        --output none
      echo "  ✓ Azure Service Bus Data Owner granted"
    fi
  else
    echo "  ✓ Azure Service Bus Data Owner already granted"
  fi
fi
echo ""

# Step 6: Setup workload identity federation if in workload-identity mode
if [[ "$AUTH_MODE" == "workload-identity" ]]; then
  echo "→ Setting up workload identity federation..."
  
  # Service accounts that need Azure access
  SERVICE_ACCOUNTS=("expense-api" "workflow-engine" "notification-svc")
  
  for SA_NAME in "${SERVICE_ACCOUNTS[@]}"; do
    echo "  → Configuring service account: $SA_NAME"
    
    # Create federated credential
    FED_CRED_NAME="radiusclaim-${SA_NAME}"
    FED_SUBJECT="system:serviceaccount:${NAMESPACE}:${SA_NAME}"
    
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
  echo ""
fi

# Step 7: Create Kubernetes secrets (only if needed)
if [[ "$AUTH_MODE" == "service-principal" ]]; then
  echo "→ Creating Kubernetes secrets..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would create secret: azure-entra-auth"
    echo "  [DRY RUN] Would create secret: pubsub-secrets"
  else
    kubectl create secret generic azure-entra-auth \
      --from-literal=azureClientSecret="$AZURE_CLIENT_SECRET_VALUE" \
      --namespace="$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    kubectl create secret generic pubsub-secrets \
      --from-literal=connectionString="$SERVICEBUS_CONN" \
      --namespace="$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    echo "  ✓ Secrets created"
  fi
  echo ""
else
  echo "→ Skipping secret creation (workload identity mode - zero secrets required)"
  echo ""
fi

# Step 8: Generate Dapr component manifests
echo "→ Generating Dapr component manifests..."
cat > dapr-components-generated.yaml <<EOF_COMPONENTS
---
# Auto-generated Dapr Components
# Generated by: deploy-dapr-components.sh
# Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Application: $APP_NAME
# Environment: $ENV_NAME
# Namespace: $NAMESPACE
# Auth mode: $AUTH_MODE

apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: $NAMESPACE
spec:
  type: state.azure.blobstorage
  version: v2
  metadata:
  - name: accountName
    value: "$STORAGE_ACCOUNT"
  - name: containerName
    value: "$CONTAINER_NAME"
  - name: azureClientId
    value: "$AZURE_CLIENT_ID_VALUE"
  - name: azureEnvironment
    value: "AZUREPUBLICCLOUD"
EOF_COMPONENTS

if [[ "$AUTH_MODE" == "service-principal" ]]; then
  cat >> dapr-components-generated.yaml <<EOF_COMPONENTS
  - name: azureTenantId
    value: "$AZURE_TENANT_ID"
  - name: azureClientSecret
    secretKeyRef:
      name: azure-entra-auth
      key: azureClientSecret
EOF_COMPONENTS
fi

cat >> dapr-components-generated.yaml <<EOF_COMPONENTS
---
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
  namespace: $NAMESPACE
spec:
  type: pubsub.azure.servicebus.topics
  version: v1
  metadata:
EOF_COMPONENTS

if [[ "$AUTH_MODE" == "workload-identity" ]]; then
  cat >> dapr-components-generated.yaml <<EOF_COMPONENTS
  - name: namespaceName
    value: "$SERVICEBUS_NAMESPACE.servicebus.windows.net"
  - name: azureClientId
    value: "$AZURE_CLIENT_ID_VALUE"
  - name: disableEntityManagement
    value: "true"
---
EOF_COMPONENTS
else
  cat >> dapr-components-generated.yaml <<EOF_COMPONENTS
  - name: connectionString
    secretKeyRef:
      name: pubsub-secrets
      key: connectionString
  - name: disableEntityManagement
    value: "true"
---
EOF_COMPONENTS
fi

cat >> dapr-components-generated.yaml <<EOF_COMPONENTS
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: platform-secrets
  namespace: $NAMESPACE
spec:
  type: secretstores.azure.keyvault
  version: v1
  metadata:
  - name: vaultName
    value: "$VAULT_NAME"
  - name: azureClientId
    value: "$AZURE_CLIENT_ID_VALUE"
  - name: azureEnvironment
    value: "AZUREPUBLICCLOUD"
EOF_COMPONENTS

if [[ "$AUTH_MODE" == "service-principal" ]]; then
  cat >> dapr-components-generated.yaml <<EOF_COMPONENTS
  - name: azureTenantId
    value: "$AZURE_TENANT_ID"
  - name: azureClientSecret
    secretKeyRef:
      name: azure-entra-auth
      key: azureClientSecret
EOF_COMPONENTS
fi

echo "  ✓ Manifest generated: dapr-components-generated.yaml"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=========================================="
  echo "DRY RUN: Component manifests generated"
  echo "=========================================="
  echo "To apply manually:"
  echo "  kubectl apply -f dapr-components-generated.yaml"
  echo ""
  exit 0
fi

# Step 9: Apply Dapr components
echo "→ Applying Dapr components to cluster..."
kubectl apply -f dapr-components-generated.yaml

echo ""
echo "→ Verifying component deployment..."
sleep 2

COMPONENTS_JSON=$(kubectl get components -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
if echo "$COMPONENTS_JSON" | jq -e '[.items[].metadata.name] | contains(["statestore", "pubsub", "platform-secrets"])' >/dev/null 2>&1; then
  echo "  ✓ Components deployed successfully"
  kubectl get components -n "$NAMESPACE"
else
  echo "  ⚠ Warning: Expected statestore, pubsub, and platform-secrets in namespace '$NAMESPACE'"
  kubectl get components -n "$NAMESPACE"
  exit 5
fi

# Step 10: Patch deployments with workload identity labels if in workload-identity mode
if [[ "$AUTH_MODE" == "workload-identity" ]]; then
  echo ""
  echo "→ Patching deployments with workload identity labels..."
  
  DEPLOYMENTS=("expense-api" "workflow-engine" "notification-svc")
  
  for DEPLOY_NAME in "${DEPLOYMENTS[@]}"; do
    echo "  → Patching deployment: $DEPLOY_NAME"
    
    kubectl patch deployment "$DEPLOY_NAME" -n "$NAMESPACE" --type=merge -p='
{
  "spec": {
    "template": {
      "metadata": {
        "labels": {
          "azure.workload.identity/use": "true"
        }
      },
      "spec": {
        "serviceAccountName": "'"$DEPLOY_NAME"'"
      }
    }
  }
}' >/dev/null 2>&1 && echo "    ✓ Deployment patched" || echo "    ⚠ Deployment patch may have failed"
  done
  
  echo ""
  echo "  → Restarting deployments to pick up new configuration..."
  kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc -n "$NAMESPACE" >/dev/null 2>&1
  echo "  ✓ Deployments restarted"
fi

echo ""
echo "=========================================="
echo "Deployment Complete"
echo "=========================================="
echo ""
echo "Workload Identity Configuration:"
echo "  Managed Identity:  $MANAGED_IDENTITY_NAME"
echo "  Client ID:         $AZURE_CLIENT_ID_VALUE"
echo ""
echo "Next steps:"
echo "  1. Wait for pods to restart:"
echo "     kubectl rollout status deployment -n $NAMESPACE --timeout=120s"
echo ""
echo "  2. Check Dapr sidecar logs:"
echo "     kubectl logs -n $NAMESPACE deployment/expense-api -c daprd --tail=30"
echo ""
echo "  3. Verify components loaded:"
echo "     kubectl logs -n $NAMESPACE -l app=expense-api -c daprd --tail=30 | grep 'component loaded'"
echo ""

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/platform-common.sh"

# ---------------------------------------------------------------------------
# DEPRECATED SCRIPT — DO NOT USE FOR NEW DEPLOYMENTS
# ---------------------------------------------------------------------------
# This script deploys per-app Dapr Component CRDs using Service Principal auth
# (connection strings). It is no longer the canonical deployment path.
#
# Replacement: deploy-dapr-components-workload-identity.sh
#   Performs per-cluster workload identity bootstrap (first deploy only).
#   Manages federated credentials and Kubernetes service account configuration.
#
# This file is retained as a reference fallback. It WILL be removed in a future cleanup.
# ---------------------------------------------------------------------------
log_warning "DEPRECATED: deploy-dapr-components.sh is no longer the canonical deployment path."
log_warning "  → Replacement: deploy-dapr-components-workload-identity.sh"
log_warning "  → This script uses Service Principal auth (connection strings) — NOT workload identity."
log_warning "  → It is retained as a reference fallback only. Do not use for new deployments."

# deploy-dapr-components.sh
#
# Automates the deployment of Dapr Component objects into the Kubernetes cluster
# after Radius app deployment. This script bridges the gap where Radius recipes
# provision Azure backing resources but do NOT automatically project Dapr Component CRDs.
#
# Usage:
#   ./scripts/deploy-dapr-components.sh [OPTIONS]
#
# Options:
#   --app-name <name>          Radius application name (default: radiusclaim)
#   --env-name <name>          Radius environment name (default: azure)
#   --resource-group <name>    Azure resource group (required)
#   --namespace <name>         Kubernetes namespace override (auto-detected if not provided)
#   --dry-run                  Generate component YAMLs without applying
#   --help                     Show this help message
#
# Prerequisites:
#   - rad CLI (Radius application must be deployed)
#   - kubectl (Kubernetes cluster access)
#   - az CLI (Azure credentials configured)
#   - jq (JSON processor)
#   - Runtime auth inputs for the statestore path:
#       * Service principal: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID
#       * Workload identity / federated service principal: AZURE_CLIENT_ID, AZURE_TENANT_ID
#       * Optional override for RBAC repair: AZURE_PRINCIPAL_ID
#
# Exit codes:
#   0 - Success
#   1 - Missing prerequisites
#   2 - Missing required parameters
#   3 - Radius resource not found
#   4 - Azure auth/resource lookup failed
#   5 - Kubernetes deployment failed

APP_NAME="${DEFAULT_APP_NAME}"
ENV_NAME="${DEFAULT_ENV_NAME}"
RESOURCE_GROUP=""
NAMESPACE=""
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
    --namespace)
      NAMESPACE="$2"
      shift 2
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

if [[ -z "$NAMESPACE" ]]; then
  ENV_JSON=$(rad env show "$ENV_NAME" -o json 2>/dev/null || echo "{}")
  ENV_NAMESPACE=$(echo "$ENV_JSON" | jq -r '.properties.compute.namespace // empty')

  if [[ -z "$ENV_NAMESPACE" ]]; then
    echo "Error: Could not auto-detect namespace. Please provide --namespace"
    exit 3
  fi

  NAMESPACE="${ENV_NAMESPACE}-${APP_NAME}"
fi

AZURE_TENANT_ID_VALUE="${AZURE_TENANT_ID:-$(az account show --query tenantId -o tsv 2>/dev/null || echo "")}"
AZURE_CLIENT_ID_VALUE="${AZURE_CLIENT_ID:-}"
AZURE_CLIENT_SECRET_VALUE="${AZURE_CLIENT_SECRET:-}"
AZURE_PRINCIPAL_ID_VALUE="${AZURE_PRINCIPAL_ID:-}"

if [[ -z "$AZURE_CLIENT_ID_VALUE" ]] || [[ -z "$AZURE_TENANT_ID_VALUE" ]]; then
  echo "Error: AZURE_CLIENT_ID and AZURE_TENANT_ID are required for the Microsoft Entra statestore path"
  echo "  Service principal mode also needs AZURE_CLIENT_SECRET"
  exit 4
fi

if [[ -z "$AZURE_PRINCIPAL_ID_VALUE" ]]; then
  AZURE_PRINCIPAL_ID_VALUE=$(az ad sp show --id "$AZURE_CLIENT_ID_VALUE" --query id -o tsv 2>/dev/null || echo "")
fi

if [[ -z "$AZURE_PRINCIPAL_ID_VALUE" ]]; then
  echo "Error: Could not resolve Microsoft Entra principal object ID"
  echo "  Set AZURE_PRINCIPAL_ID explicitly or ensure 'az ad sp show --id \"$AZURE_CLIENT_ID_VALUE\"' succeeds"
  exit 4
fi

if [[ -n "$AZURE_CLIENT_SECRET_VALUE" ]]; then
  DAPR_AUTH_MODE="service-principal"
else
  DAPR_AUTH_MODE="workload-identity"
fi

echo "=========================================="
echo "Deploying Dapr Components"
echo "=========================================="
echo "Application:     $APP_NAME"
echo "Environment:     $ENV_NAME"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Namespace:       $NAMESPACE"
echo "Auth Mode:       Microsoft Entra ($DAPR_AUTH_MODE)"
echo "Dry Run:         $DRY_RUN"
echo ""

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

echo "→ Validating Azure access required for backfill..."
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
SERVICEBUS_CONN=$(az servicebus namespace authorization-rule keys list \
  --resource-group "$RESOURCE_GROUP" \
  --namespace-name "$SERVICEBUS_NAMESPACE" \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString \
  -o tsv 2>/dev/null || echo "")

if [[ -z "$STORAGE_ACCOUNT_ID" ]] || [[ -z "$KEYVAULT_ID" ]] || [[ -z "$SERVICEBUS_CONN" ]]; then
  echo "Error: Failed to retrieve required Azure resource details"
  echo "  Storage Account ID:     ${STORAGE_ACCOUNT_ID:+FOUND}${STORAGE_ACCOUNT_ID:-NOT FOUND}"
  echo "  Key Vault ID:           ${KEYVAULT_ID:+FOUND}${KEYVAULT_ID:-NOT FOUND}"
  echo "  Service Bus Conn Str:   ${SERVICEBUS_CONN:+FOUND}${SERVICEBUS_CONN:-NOT FOUND}"
  exit 4
fi

STORAGE_ROLE_ASSIGNMENT_COUNT=$(az role assignment list \
  --assignee-object-id "$AZURE_PRINCIPAL_ID_VALUE" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ACCOUNT_ID" \
  --query 'length(@)' \
  -o tsv 2>/dev/null || echo "")

if [[ -z "$STORAGE_ROLE_ASSIGNMENT_COUNT" || "$STORAGE_ROLE_ASSIGNMENT_COUNT" == "0" ]]; then
  echo "  → Storage Blob Data Contributor assignment missing for $AZURE_CLIENT_ID_VALUE"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would grant Storage Blob Data Contributor on $STORAGE_ACCOUNT_ID"
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
  -o tsv 2>/dev/null || echo "")

if [[ -z "$KEYVAULT_ROLE_ASSIGNMENT_COUNT" || "$KEYVAULT_ROLE_ASSIGNMENT_COUNT" == "0" ]]; then
  echo "  → Key Vault Secrets User assignment missing for $AZURE_CLIENT_ID_VALUE"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would grant Key Vault Secrets User on $KEYVAULT_ID"
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

echo "  ✓ Service Bus connection string retrieved"
echo ""

echo "→ Creating Kubernetes secrets..."
if [[ "$DRY_RUN" == "true" ]]; then
  [[ -n "$AZURE_CLIENT_SECRET_VALUE" ]] && echo "  [DRY RUN] Would create secret: azure-entra-auth"
  echo "  [DRY RUN] Would create secret: pubsub-secrets"
else
  if [[ -n "$AZURE_CLIENT_SECRET_VALUE" ]]; then
    kubectl create secret generic azure-entra-auth \
      --from-literal=azureClientSecret="$AZURE_CLIENT_SECRET_VALUE" \
      --namespace="$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  kubectl create secret generic pubsub-secrets \
    --from-literal=connectionString="$SERVICEBUS_CONN" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "  ✓ Secrets created"
fi
echo ""

echo "→ Generating Dapr component manifests..."
cat > dapr-components-generated.yaml <<EOF_COMPONENTS
---
# Auto-generated Dapr Components
# Generated by: deploy-dapr-components.sh
# Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Application: $APP_NAME
# Environment: $ENV_NAME
# Namespace: $NAMESPACE
# Auth mode: Microsoft Entra ($DAPR_AUTH_MODE)

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
  - name: azureTenantId
    value: "$AZURE_TENANT_ID_VALUE"
  - name: azureClientId
    value: "$AZURE_CLIENT_ID_VALUE"
  - name: azureEnvironment
    value: "AZUREPUBLICCLOUD"
EOF_COMPONENTS

if [[ -n "$AZURE_CLIENT_SECRET_VALUE" ]]; then
  cat >> dapr-components-generated.yaml <<'EOF_COMPONENTS'
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
  - name: connectionString
    secretKeyRef:
      name: pubsub-secrets
      key: connectionString
  - name: disableEntityManagement
    value: "true"
---
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
  - name: azureTenantId
    value: "$AZURE_TENANT_ID_VALUE"
  - name: azureClientId
    value: "$AZURE_CLIENT_ID_VALUE"
  - name: azureEnvironment
    value: "AZUREPUBLICCLOUD"
EOF_COMPONENTS

if [[ -n "$AZURE_CLIENT_SECRET_VALUE" ]]; then
  cat >> dapr-components-generated.yaml <<'EOF_COMPONENTS'
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

echo ""
echo "=========================================="
echo "Deployment Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Verify component status:"
echo "     kubectl get components -n $NAMESPACE"
echo ""
echo "  2. Check pod logs to ensure Dapr sidecars can connect:"
echo "     kubectl logs -n $NAMESPACE deployment/expense-api -c daprd"
echo ""
echo "  3. Test the application:"
echo "     kubectl port-forward -n $NAMESPACE svc/expense-api 8080:8080"
echo "     curl http://localhost:8080/app"
echo ""

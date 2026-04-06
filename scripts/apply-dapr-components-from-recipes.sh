#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# apply-dapr-components-from-recipes.sh — Create Dapr Components from Recipe Metadata
# ──────────────────────────────────────────────────────────────────────────────
# Reads recipe outputs from Radius and generates Kubernetes Dapr Component CRDs
# using workload identity authentication. This is the Phase 2 missing piece: recipes
# provision Azure resources, but Kubernetes components must be created separately.
#
# USAGE:
#   scripts/apply-dapr-components-from-recipes.sh \
#     --environment <radius-env> \
#     --application <radius-app> \
#     --namespace <k8s-namespace> \
#     --tenant-id <azure-tenant-id> \
#     --client-id <dapr-workload-identity-client-id>
#
# PREREQUISITES:
#   - rad CLI authenticated and connected to workspace
#   - kubectl configured for target cluster
#   - Radius environment deployed with recipes
#   - Workload identity federated credential configured
#
# WHAT IT DOES:
#   1. Queries Radius for recipe outputs (stateStore, pubSubBroker, secretStore)
#   2. Extracts resourceMetadata.dapr from each recipe output
#   3. Generates Kubernetes Dapr Component manifests dynamically
#   4. Applies components to the target namespace
#
# EXIT CODES:
#   0 — All components created successfully
#   1 — Missing required parameters or dependencies
#   2 — Radius query failed (environment/application not found)
#   3 — kubectl apply failed
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Logging helpers ───────────────────────────────────────────────────────────
log_info() { echo "✓ $*" >&2; }
log_warn() { echo "⚠ $*" >&2; }
log_error() { echo "✗ $*" >&2; }
log_fatal() { log_error "$*"; exit "${2:-1}"; }

# ── Parse arguments ───────────────────────────────────────────────────────────
ENVIRONMENT=""
APPLICATION=""
NAMESPACE=""
TENANT_ID=""
CLIENT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment) ENVIRONMENT="$2"; shift 2 ;;
    --application) APPLICATION="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    *) log_fatal "Unknown argument: $1" 1 ;;
  esac
done

# ── Validate required parameters ─────────────────────────────────────────────
[[ -z "$ENVIRONMENT" ]] && log_fatal "Missing --environment" 1
[[ -z "$APPLICATION" ]] && log_fatal "Missing --application" 1
[[ -z "$NAMESPACE" ]] && log_fatal "Missing --namespace" 1
[[ -z "$TENANT_ID" ]] && log_fatal "Missing --tenant-id" 1
[[ -z "$CLIENT_ID" ]] && log_fatal "Missing --client-id" 1

# ── Check dependencies ────────────────────────────────────────────────────────
command -v rad >/dev/null 2>&1 || log_fatal "rad CLI not found" 1
command -v kubectl >/dev/null 2>&1 || log_fatal "kubectl not found" 1
command -v jq >/dev/null 2>&1 || log_fatal "jq not found" 1

log_info "Creating Dapr components for application '$APPLICATION' in namespace '$NAMESPACE'"

# ── Query Radius for Dapr resource outputs ───────────────────────────────────
# Radius stores recipe outputs under Applications.Dapr/<type>/<name>

query_recipe_metadata() {
  local resource_type="$1"
  local resource_name="$2"
  
  log_info "Querying $resource_type/$resource_name..."
  
  rad resource show "$resource_type" "$resource_name" \
    --application "$APPLICATION" \
    --output json 2>/dev/null || {
    log_warn "Resource $resource_type/$resource_name not found or not accessible"
    echo "{}"
  }
}

STATESTORE_JSON=$(query_recipe_metadata "Applications.Dapr/stateStores" "statestore")
PUBSUB_JSON=$(query_recipe_metadata "Applications.Dapr/pubSubBrokers" "pubsub")
SECRETS_JSON=$(query_recipe_metadata "Applications.Dapr/secretStores" "platform-secrets")

# ── Extract Azure resource names from Radius outputResources ───────────────────
# Radius API returns only Azure resource IDs in outputResources[], not recipe outputs.
# Parse the IDs to extract resource names for Dapr component metadata.
#
# The state store can be either Azure Blob Storage (legacy) or PostgreSQL (new).
# We detect the type from the recipe metadata and extract the appropriate values.

# Detect state store type from recipe metadata
STATESTORE_TYPE=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentType // "state.azure.blobstorage"')
log_info "Detected state store type: $STATESTORE_TYPE"

# Initialize state store variables
STORAGE_ACCOUNT=""
CONTAINER_NAME=""
POSTGRES_SERVER=""
POSTGRES_DATABASE=""
POSTGRES_USER=""
CONNECTION_STRING=""
STATESTORE_TENANT_ID=""
STATESTORE_CLIENT_ID=""
STATESTORE_ENVIRONMENT=""

if [[ "$STATESTORE_TYPE" == "state.postgresql" ]]; then
  # PostgreSQL state store: Extract from outputResources
  log_info "Extracting PostgreSQL state store configuration..."
  
  POSTGRES_SERVER=$(echo "$STATESTORE_JSON" | jq -r '
    .properties.status.outputResources[]?
    | select(.id | test("/Microsoft.DBforPostgreSQL/flexibleServers/[^/]+$"))
    | .id
    | split("/")[-1]
  ')
  
  # Get connection details from resourceMetadata
  POSTGRES_DATABASE=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.databaseName // "dapr_state"')
  POSTGRES_USER=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.databaseUser // "dapr_app"')
  CONNECTION_STRING=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.values.connectionString // ""')
  
  # Get Entra auth details from recipe metadata
  STATESTORE_TENANT_ID=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // ""')
  STATESTORE_CLIENT_ID=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // ""')
  STATESTORE_ENVIRONMENT=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // "AZUREPUBLICCLOUD"')
  
  if [[ -z "$POSTGRES_SERVER" ]] || [[ -z "$CONNECTION_STRING" ]]; then
    log_error "Failed to extract PostgreSQL server or connection string. Check Radius recipe deployment."
    exit 1
  fi
  
  log_info "Extracted PostgreSQL state store:"
  log_info "  Server: $POSTGRES_SERVER"
  log_info "  Database: $POSTGRES_DATABASE"
  log_info "  User: $POSTGRES_USER"
else
  # Azure Blob Storage state store (legacy): Extract from outputResources
  log_info "Extracting Azure Blob Storage state store configuration..."
  
  STORAGE_ACCOUNT=$(echo "$STATESTORE_JSON" | jq -r '
    .properties.status.outputResources[]?
    | select(.id | test("/Microsoft.Storage/storageAccounts/[^/]+$"))
    | .id
    | split("/")[-1]
  ')
  
  CONTAINER_NAME="expense-state"
  
  # Get Entra auth details from recipe metadata, fall back to script parameters
  STATESTORE_TENANT_ID=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // ""')
  STATESTORE_CLIENT_ID=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // ""')
  STATESTORE_ENVIRONMENT=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // "AZUREPUBLICCLOUD"')
  
  # Fall back to script parameters if not in recipe metadata (backward compatibility)
  STATESTORE_TENANT_ID=${STATESTORE_TENANT_ID:-$TENANT_ID}
  STATESTORE_CLIENT_ID=${STATESTORE_CLIENT_ID:-$CLIENT_ID}
  
  if [[ -z "$STORAGE_ACCOUNT" ]]; then
    log_error "Failed to extract storage account name from statestore resource. Check Radius recipe deployment."
    exit 1
  fi
  
  log_info "Extracted Azure Blob Storage state store:"
  log_info "  Storage Account: $STORAGE_ACCOUNT"
  log_info "  Container: $CONTAINER_NAME"
fi

# Pub/Sub: Extract Service Bus namespace name from the /Microsoft.ServiceBus/namespaces/ resource
# Append .servicebus.windows.net — Dapr requires the FQDN, not the short name
SERVICEBUS_NAMESPACE=$(echo "$PUBSUB_JSON" | jq -r '
  .properties.status.outputResources[]?
  | select(.id | test("/Microsoft.ServiceBus/namespaces/[^/]+$"))
  | .id
  | split("/")[-1]
')
if [[ -n "$SERVICEBUS_NAMESPACE" ]] && [[ "$SERVICEBUS_NAMESPACE" != *".servicebus.windows.net" ]]; then
  SERVICEBUS_NAMESPACE="${SERVICEBUS_NAMESPACE}.servicebus.windows.net"
fi

# Secrets: Extract Key Vault name from the /Microsoft.KeyVault/vaults/ resource
KEYVAULT_NAME=$(echo "$SECRETS_JSON" | jq -r '
  .properties.status.outputResources[]?
  | select(.id | test("/Microsoft.KeyVault/vaults/[^/]+$"))
  | .id
  | split("/")[-1]
')

# Validate extracted values
if [[ -z "$SERVICEBUS_NAMESPACE" ]]; then
  log_error "Failed to extract Service Bus namespace from pubsub resource. Check Radius recipe deployment."
  exit 1
fi

if [[ -z "$KEYVAULT_NAME" ]]; then
  log_error "Failed to extract Key Vault name from platform-secrets resource. Check Radius recipe deployment."
  exit 1
fi

log_info "Extracted Azure resources:"
log_info "  Service Bus Namespace: $SERVICEBUS_NAMESPACE"
log_info "  Key Vault: $KEYVAULT_NAME"

# ── Generate Dapr Component manifests ─────────────────────────────────────────
TEMP_MANIFEST=$(mktemp)
trap 'rm -f "$TEMP_MANIFEST"' EXIT

# Build state store component based on type
STATE_STORE_COMPONENT=""
if [[ "$STATESTORE_TYPE" == "state.postgresql" ]]; then
  STATE_STORE_COMPONENT=$(cat <<'COMPONENT'
---
# State Store Component - PostgreSQL (Workload Identity)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: $NAMESPACE
spec:
  type: state.postgresql
  version: v2
  metadata:
  - name: connectionString
    value: "$CONNECTION_STRING"
  - name: useAzureAD
    value: "true"
  - name: azureTenantId
    value: "$STATESTORE_TENANT_ID"
  - name: azureClientId
    value: "$STATESTORE_CLIENT_ID"
  - name: azureEnvironment
    value: "$STATESTORE_ENVIRONMENT"
  - name: actorStateStore
    value: "true"
COMPONENT
)
else
  STATE_STORE_COMPONENT=$(cat <<'COMPONENT'
---
# State Store Component - Azure Blob Storage (Workload Identity)
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
    value: "$STATESTORE_TENANT_ID"
  - name: azureClientId
    value: "$STATESTORE_CLIENT_ID"
  - name: azureEnvironment
    value: "$STATESTORE_ENVIRONMENT"
  - name: actorStateStore
    value: "true"
COMPONENT
)
fi

cat > "$TEMP_MANIFEST" <<EOF
$STATE_STORE_COMPONENT
---
# Pub/Sub Component - Azure Service Bus Topics (Workload Identity)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
  namespace: $NAMESPACE
spec:
  type: pubsub.azure.servicebus.topics
  version: v1
  metadata:
  - name: namespaceName
    value: "$SERVICEBUS_NAMESPACE"
  - name: azureTenantId
    value: "$TENANT_ID"
  - name: azureClientId
    value: "$CLIENT_ID"
  - name: azureEnvironment
    value: "AZUREPUBLICCLOUD"
  - name: disableEntityManagement
    value: "false"
---
# Secret Store Component - Azure Key Vault (Workload Identity)
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
    value: "$KEYVAULT_NAME"
  - name: azureTenantId
    value: "$TENANT_ID"
  - name: azureClientId
    value: "$CLIENT_ID"
  - name: azureEnvironment
    value: "AZUREPUBLICCLOUD"
EOF

log_info "Generated Dapr component manifest at $TEMP_MANIFEST"
log_info "Applying components to namespace '$NAMESPACE'..."

# ── Apply components to Kubernetes ────────────────────────────────────────────
if kubectl apply -f "$TEMP_MANIFEST"; then
  log_info "Successfully created Dapr components"
  
  # Verify components were created
  log_info "Verifying components..."
  kubectl get components -n "$NAMESPACE" -o wide
  
  exit 0
else
  log_fatal "Failed to apply Dapr components" 3
fi

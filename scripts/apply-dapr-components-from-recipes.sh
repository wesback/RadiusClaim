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
DAPR_PG_USER=""  # managed identity display name (PostgreSQL connection user)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment) ENVIRONMENT="$2"; shift 2 ;;
    --application) APPLICATION="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --dapr-pg-user) DAPR_PG_USER="$2"; shift 2 ;;
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
# We detect the type from the ARM resource type in outputResources (Radius v0.56
# does not surface custom recipe outputs in the API response — only outputResources).

# Detect state store type from outputResources ARM resource types.
# Fall back to legacy blob storage if neither type is found.
_has_postgres=$(echo "$STATESTORE_JSON" | jq -r '
  [.properties.status.outputResources[]? | .id]
  | map(select(test("/Microsoft.DBforPostgreSQL/flexibleServers/[^/]+$")))
  | length > 0
')
if [[ "$_has_postgres" == "true" ]]; then
  STATESTORE_TYPE="state.postgresql"
else
  # Legacy path: check resourceMetadata first, then default to blob storage
  STATESTORE_TYPE=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentType // "state.azure.blobstorage"')
fi
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
  
  # Get connection details from recipe outputs
  # connectionString can be in values (top-level output) or resourceMetadata.dapr.metadata
  POSTGRES_DATABASE=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.values.databaseName // .properties.status.resourceMetadata.databaseName // "dapr_state"')
  POSTGRES_USER=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.values.databaseUser // .properties.status.resourceMetadata.databaseUser // ""')
  # Prefer explicit --dapr-pg-user override (managed identity display name); fall back to recipe output.
  [[ -z "$POSTGRES_USER" ]] && POSTGRES_USER="${DAPR_PG_USER}"
  [[ -z "$POSTGRES_USER" ]] && POSTGRES_USER="dapr_app"
  CONNECTION_STRING=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.values.connectionString // .properties.status.resourceMetadata.dapr.metadata.connectionString // ""')
  
  # Fallback: construct connection string from server FQDN if recipe metadata paths are empty.
  # Radius v0.56 does not return custom recipe outputs in the API response; query Azure for FQDN.
  if [[ -z "$CONNECTION_STRING" ]] && [[ -n "$POSTGRES_SERVER" ]]; then
    if command -v az &>/dev/null; then
      POSTGRES_FQDN="$(az postgres flexible-server show \
        --name "$POSTGRES_SERVER" \
        --query fullyQualifiedDomainName -o tsv 2>/dev/null || true)"
    fi
    [[ -z "$POSTGRES_FQDN" ]] && POSTGRES_FQDN="${POSTGRES_SERVER}.postgres.database.azure.com"
    CONNECTION_STRING="host=${POSTGRES_FQDN} port=5432 database=${POSTGRES_DATABASE} user=${POSTGRES_USER} sslmode=require"
    log_warn "Constructed connection string from server FQDN (Radius v0.56 does not surface recipe output values)"
  fi

  # Get Entra auth details from recipe metadata
  STATESTORE_TENANT_ID=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // .properties.status.values.azureTenantId // ""')
  STATESTORE_CLIENT_ID=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // .properties.status.values.azureClientId // ""')
  STATESTORE_ENVIRONMENT=$(echo "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // "AZUREPUBLICCLOUD"')
  
  # Fall back to script parameters if not in recipe metadata
  STATESTORE_TENANT_ID=${STATESTORE_TENANT_ID:-$TENANT_ID}
  STATESTORE_CLIENT_ID=${STATESTORE_CLIENT_ID:-$CLIENT_ID}
  
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

# Extract Entra auth details for Pub/Sub
PUBSUB_TENANT_ID=$(echo "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // ""')
PUBSUB_CLIENT_ID=$(echo "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // ""')
PUBSUB_ENVIRONMENT=$(echo "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // "AZUREPUBLICCLOUD"')

# Fall back to script parameters if not in recipe metadata
PUBSUB_TENANT_ID=${PUBSUB_TENANT_ID:-$TENANT_ID}
PUBSUB_CLIENT_ID=${PUBSUB_CLIENT_ID:-$CLIENT_ID}

# Secrets: Extract Key Vault name from the /Microsoft.KeyVault/vaults/ resource
KEYVAULT_NAME=$(echo "$SECRETS_JSON" | jq -r '
  .properties.status.outputResources[]?
  | select(.id | test("/Microsoft.KeyVault/vaults/[^/]+$"))
  | .id
  | split("/")[-1]
')

# Extract Entra auth details for Key Vault
KEYVAULT_TENANT_ID=$(echo "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // ""')
KEYVAULT_CLIENT_ID=$(echo "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // ""')
KEYVAULT_ENVIRONMENT=$(echo "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // "AZUREPUBLICCLOUD"')

# Fall back to script parameters if not in recipe metadata
KEYVAULT_TENANT_ID=${KEYVAULT_TENANT_ID:-$TENANT_ID}
KEYVAULT_CLIENT_ID=${KEYVAULT_CLIENT_ID:-$CLIENT_ID}

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

# Build complete Dapr component manifest with proper variable substitution
# Write directly to temp file (don't use intermediate variables with heredoc)
cat > "$TEMP_MANIFEST" <<EOF
---
# State Store Component (Type depends on recipe: PostgreSQL or Blob Storage)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: $NAMESPACE
spec:
  type: $(if [[ "$STATESTORE_TYPE" == "state.postgresql" ]]; then echo "state.postgresql"; else echo "state.azure.blobstorage"; fi)
  version: v2
  metadata:
EOF

# Append state store specific metadata
if [[ "$STATESTORE_TYPE" == "state.postgresql" ]]; then
  cat >> "$TEMP_MANIFEST" <<EOF
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
  - name: keyPrefix
    value: "none"
EOF
else
  cat >> "$TEMP_MANIFEST" <<EOF
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
  - name: keyPrefix
    value: "none"
EOF
fi

# Pub/Sub component
cat >> "$TEMP_MANIFEST" <<EOF
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
    value: "$PUBSUB_TENANT_ID"
  - name: azureClientId
    value: "$PUBSUB_CLIENT_ID"
  - name: azureEnvironment
    value: "$PUBSUB_ENVIRONMENT"
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
    value: "$KEYVAULT_TENANT_ID"
  - name: azureClientId
    value: "$KEYVAULT_CLIENT_ID"
  - name: azureEnvironment
    value: "$KEYVAULT_ENVIRONMENT"
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

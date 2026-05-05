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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log_info "Creating Dapr components for application '$APPLICATION' in namespace '$NAMESPACE'"

# ── Query Radius for Dapr resource outputs ───────────────────────────────────
# Radius stores recipe outputs under Applications.Dapr/<type>/<name>.
# Prefer live discovery from the app's resources, then fall back to the legacy
# sample resource names for backward compatibility.

query_recipe_resource() {
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

list_recipe_resources() {
  local resource_type="$1"
  local list_json

  list_json="$(rad resource list "$resource_type" \
    --application "$APPLICATION" \
    --output json 2>/dev/null || true)"
  list_json="$(printf '%s\n' "$list_json" | sed -n '/^\[/,$p')"

  if [[ -n "$list_json" ]] && printf '%s' "$list_json" | jq empty >/dev/null 2>&1; then
    printf '%s' "$list_json"
  else
    printf '[]'
  fi
}

resolve_recipe_resource_name() {
  local resource_type="$1"
  local legacy_name="$2"
  local list_json resolved_name match_count

  list_json="$(list_recipe_resources "$resource_type")"
  resolved_name="$(printf '%s' "$list_json" | jq -r --arg env "$ENVIRONMENT" --arg legacy "$legacy_name" '
    def has_recipe_contract:
      (.properties.status.resourceMetadata.dapr? != null)
      or (.properties.status.values? != null)
      or ((.properties.status.outputResources? | length) > 0);
    def env_matches:
      (.properties.environment? // "") as $actual
      | ($env // "") as $expected
      | ($expected == "")
        or (($actual | ascii_downcase) == ($expected | ascii_downcase))
        or (($actual | ascii_downcase) | endswith("/" + ($expected | ascii_downcase)));

    [ .[] | select(has_recipe_contract) | select(env_matches) ] as $matches
    | if ($matches | length) == 0 then
        ([ .[] | select(has_recipe_contract) ] as $all
         | if ($all | map(select(.name == $legacy)) | length) > 0 then
             ($all | map(select(.name == $legacy))[0].name)
           else
             ($all[0].name // "")
           end)
      elif ($matches | map(select(.name == $legacy)) | length) > 0 then
        ($matches | map(select(.name == $legacy))[0].name)
      else
        ($matches[0].name // "")
      end
  ')"

  match_count="$(printf '%s' "$list_json" | jq -r --arg env "$ENVIRONMENT" '
    def has_recipe_contract:
      (.properties.status.resourceMetadata.dapr? != null)
      or (.properties.status.values? != null)
      or ((.properties.status.outputResources? | length) > 0);
    def env_matches:
      (.properties.environment? // "") as $actual
      | ($env // "") as $expected
      | ($expected == "")
        or (($actual | ascii_downcase) == ($expected | ascii_downcase))
        or (($actual | ascii_downcase) | endswith("/" + ($expected | ascii_downcase)));

    [ .[] | select(has_recipe_contract) | select(env_matches) ] | length
  ')"

  if [[ "${match_count:-0}" -gt 1 ]]; then
    log_warn "Multiple $resource_type resources matched application '$APPLICATION'; using '$resolved_name'"
  fi

  if [[ -n "$resolved_name" ]]; then
    printf '%s' "$resolved_name"
  else
    printf '%s' "$legacy_name"
  fi
}

load_recipe_resource() {
  local resource_type="$1"
  local legacy_name="$2"
  local resolved_name resource_json

  resolved_name="$(resolve_recipe_resource_name "$resource_type" "$legacy_name")"
  resource_json="$(query_recipe_resource "$resource_type" "$resolved_name")"

  if ! printf '%s' "$resource_json" | jq -e '.name? != null and .name != ""' >/dev/null 2>&1 && [[ "$resolved_name" != "$legacy_name" ]]; then
    log_warn "Falling back to legacy $resource_type resource name '$legacy_name'"
    resolved_name="$legacy_name"
    resource_json="$(query_recipe_resource "$resource_type" "$resolved_name")"
  fi

  if ! printf '%s' "$resource_json" | jq -e '.name? != null and .name != ""' >/dev/null 2>&1; then
    log_fatal "Resource $resource_type/$legacy_name not found for application '$APPLICATION'" 2
  fi

  resource_json="$(printf '%s' "$resource_json" | jq -c '.')"

  printf '%s\n%s\n' "$resolved_name" "$resource_json"
}

set_metadata_default() {
  local metadata_json="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$value" ]]; then
    printf '%s' "$metadata_json"
    return
  fi

  printf '%s' "$metadata_json" | jq -c --arg key "$key" --arg value "$value" '
    if (.[$key] // "") == "" then . + {($key): $value} else . end
  '
}

render_metadata_yaml() {
  local metadata_json="$1"

  printf '%s' "$metadata_json" | jq -r '
    to_entries
    | map(select(.value != null and (.value | tostring) != ""))
    | .[]
    | "  - name: \(.key)\n    value: \(.value | tostring | @json)"
  '
}

servicebus_dns_suffix() {
  local azure_environment="${1:-AZUREPUBLICCLOUD}"
  local normalized="${azure_environment^^}"

  case "$normalized" in
    AZUREUSGOVERNMENT|AZUREUSGOVERNMENTCLOUD)
      printf '%s\n' "servicebus.usgovcloudapi.net"
      ;;
    AZURECHINA|AZURECHINACLOUD)
      printf '%s\n' "servicebus.chinacloudapi.cn"
      ;;
    *)
      printf '%s\n' "servicebus.windows.net"
      ;;
  esac
}

mapfile -t _state_resource < <(load_recipe_resource "Applications.Dapr/stateStores" "statestore")
STATESTORE_RESOURCE_NAME="${_state_resource[0]}"
STATESTORE_JSON="${_state_resource[@]:1}"

mapfile -t _pubsub_resource < <(load_recipe_resource "Applications.Dapr/pubSubBrokers" "pubsub")
PUBSUB_RESOURCE_NAME="${_pubsub_resource[0]}"
PUBSUB_JSON="${_pubsub_resource[@]:1}"

mapfile -t _secrets_resource < <(load_recipe_resource "Applications.Dapr/secretStores" "platform-secrets")
SECRETS_RESOURCE_NAME="${_secrets_resource[0]}"
SECRETS_JSON="${_secrets_resource[@]:1}"

# ── Extract component contract and Azure metadata ──────────────────────────────
# Prefer recipe-advertised Dapr metadata/outputs and fall back to outputResources
# only when the older Radius payload shape does not surface those values.
#
# The state store can be either Azure Blob Storage (legacy) or PostgreSQL (new).
# We still detect the legacy fallback path from outputResources ARM resource types.

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
STATESTORE_COMPONENT_NAME=$(printf '%s' "$STATESTORE_JSON" | jq -r --arg fallback "$STATESTORE_RESOURCE_NAME" '.properties.status.resourceMetadata.dapr.componentName // .properties.status.values.componentName // $fallback')
STATESTORE_COMPONENT_VERSION=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentVersion // "v2"')
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
STATESTORE_METADATA_JSON=$(printf '%s' "$STATESTORE_JSON" | jq -c '.properties.status.resourceMetadata.dapr.metadata // {}')

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
  POSTGRES_DATABASE=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.databaseName // .properties.status.values.databaseName // .properties.status.resourceMetadata.databaseName // "dapr_state"')
  POSTGRES_USER=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.databaseUser // .properties.status.values.databaseUser // .properties.status.resourceMetadata.databaseUser // ""')
  # Prefer explicit --dapr-pg-user override (managed identity display name); fall back to recipe output.
  [[ -z "$POSTGRES_USER" ]] && POSTGRES_USER="${DAPR_PG_USER}"
  [[ -z "$POSTGRES_USER" ]] && POSTGRES_USER="dapr_app"
  CONNECTION_STRING=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.connectionString // .properties.status.values.connectionString // ""')
  
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
  STATESTORE_TENANT_ID=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // .properties.status.values.azureTenantId // ""')
  STATESTORE_CLIENT_ID=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // .properties.status.values.azureClientId // ""')
  STATESTORE_ENVIRONMENT=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // .properties.status.values.azureEnvironment // "AZUREPUBLICCLOUD"')
  
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

  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "connectionString" "$CONNECTION_STRING")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "useAzureAD" "true")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "azureTenantId" "$STATESTORE_TENANT_ID")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "azureClientId" "$STATESTORE_CLIENT_ID")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "azureEnvironment" "$STATESTORE_ENVIRONMENT")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "actorStateStore" "$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.values.actorStateStore // "true"')")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "keyPrefix" "none")
else
  # Azure Blob Storage state store (legacy): Extract from outputResources
  log_info "Extracting Azure Blob Storage state store configuration..."
  
  STORAGE_ACCOUNT=$(printf '%s' "$STATESTORE_JSON" | jq -r '
    .properties.status.resourceMetadata.dapr.metadata.accountName
    // .properties.status.values.accountName
    // .properties.status.resourceMetadata.storageAccountName
    // (
      .properties.status.outputResources[]?
      | select(.id | test("/Microsoft.Storage/storageAccounts/[^/]+$"))
      | .id
      | split("/")[-1]
    )
    // empty
  ')
  
  CONTAINER_NAME=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.containerName // .properties.status.values.containerName // "expense-state"')
  
  # Get Entra auth details from recipe metadata, fall back to script parameters
  STATESTORE_TENANT_ID=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // .properties.status.values.azureTenantId // ""')
  STATESTORE_CLIENT_ID=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // .properties.status.values.azureClientId // ""')
  STATESTORE_ENVIRONMENT=$(printf '%s' "$STATESTORE_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // .properties.status.values.azureEnvironment // "AZUREPUBLICCLOUD"')
  
  # Fall back to script parameters if not in recipe metadata (backward compatibility)
  STATESTORE_TENANT_ID=${STATESTORE_TENANT_ID:-$TENANT_ID}
  STATESTORE_CLIENT_ID=${STATESTORE_CLIENT_ID:-$CLIENT_ID}
  
  if [[ -z "$STORAGE_ACCOUNT" ]]; then
    log_error "Failed to extract storage account name from $STATESTORE_RESOURCE_NAME resource. Check Radius recipe deployment."
    exit 1
  fi
  
  log_info "Extracted Azure Blob Storage state store:"
  log_info "  Storage Account: $STORAGE_ACCOUNT"
  log_info "  Container: $CONTAINER_NAME"

  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "accountName" "$STORAGE_ACCOUNT")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "containerName" "$CONTAINER_NAME")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "azureTenantId" "$STATESTORE_TENANT_ID")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "azureClientId" "$STATESTORE_CLIENT_ID")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "azureEnvironment" "$STATESTORE_ENVIRONMENT")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "actorStateStore" "true")
  STATESTORE_METADATA_JSON=$(set_metadata_default "$STATESTORE_METADATA_JSON" "keyPrefix" "none")
fi

# Pub/Sub: Extract Service Bus namespace name from the /Microsoft.ServiceBus/namespaces/ resource
# Append the cloud-specific Service Bus DNS suffix — Dapr requires the FQDN, not the short name
PUBSUB_COMPONENT_NAME=$(printf '%s' "$PUBSUB_JSON" | jq -r --arg fallback "$PUBSUB_RESOURCE_NAME" '.properties.status.resourceMetadata.dapr.componentName // .properties.status.values.componentName // $fallback')
PUBSUB_COMPONENT_TYPE=$(printf '%s' "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentType // "pubsub.azure.servicebus.topics"')
PUBSUB_COMPONENT_VERSION=$(printf '%s' "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentVersion // "v1"')
SERVICEBUS_NAMESPACE=$(printf '%s' "$PUBSUB_JSON" | jq -r '
  .properties.status.resourceMetadata.dapr.metadata.namespaceName
  // .properties.status.values.namespaceName
  // .properties.status.values.endpoint
  // .properties.status.resourceMetadata.endpoint
  // (
    .properties.status.outputResources[]?
    | select(.id | test("/Microsoft.ServiceBus/namespaces/[^/]+$"))
    | .id
    | split("/")[-1]
  )
  // empty
')
# Extract Entra auth details for Pub/Sub
PUBSUB_TENANT_ID=$(printf '%s' "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // .properties.status.values.azureTenantId // ""')
PUBSUB_CLIENT_ID=$(printf '%s' "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // .properties.status.values.azureClientId // ""')
PUBSUB_ENVIRONMENT=$(printf '%s' "$PUBSUB_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // .properties.status.values.azureEnvironment // "AZUREPUBLICCLOUD"')
SERVICEBUS_DNS_SUFFIX="$(servicebus_dns_suffix "$PUBSUB_ENVIRONMENT")"

if [[ -n "$SERVICEBUS_NAMESPACE" ]] && [[ "$SERVICEBUS_NAMESPACE" != *".${SERVICEBUS_DNS_SUFFIX}" ]]; then
  SERVICEBUS_NAMESPACE="${SERVICEBUS_NAMESPACE}.${SERVICEBUS_DNS_SUFFIX}"
fi

# Fall back to script parameters if not in recipe metadata
PUBSUB_TENANT_ID=${PUBSUB_TENANT_ID:-$TENANT_ID}
PUBSUB_CLIENT_ID=${PUBSUB_CLIENT_ID:-$CLIENT_ID}
PUBSUB_METADATA_JSON=$(printf '%s' "$PUBSUB_JSON" | jq -c '.properties.status.resourceMetadata.dapr.metadata // {}')
PUBSUB_METADATA_JSON=$(set_metadata_default "$PUBSUB_METADATA_JSON" "namespaceName" "$SERVICEBUS_NAMESPACE")
PUBSUB_METADATA_JSON=$(set_metadata_default "$PUBSUB_METADATA_JSON" "azureTenantId" "$PUBSUB_TENANT_ID")
PUBSUB_METADATA_JSON=$(set_metadata_default "$PUBSUB_METADATA_JSON" "azureClientId" "$PUBSUB_CLIENT_ID")
PUBSUB_METADATA_JSON=$(set_metadata_default "$PUBSUB_METADATA_JSON" "azureEnvironment" "$PUBSUB_ENVIRONMENT")
PUBSUB_METADATA_JSON=$(set_metadata_default "$PUBSUB_METADATA_JSON" "disableEntityManagement" "false")

# Secrets: Extract Key Vault name from the /Microsoft.KeyVault/vaults/ resource
SECRETS_COMPONENT_NAME=$(printf '%s' "$SECRETS_JSON" | jq -r --arg fallback "$SECRETS_RESOURCE_NAME" '.properties.status.resourceMetadata.dapr.componentName // .properties.status.values.componentName // $fallback')
SECRETS_COMPONENT_TYPE=$(printf '%s' "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentType // "secretstores.azure.keyvault"')
SECRETS_COMPONENT_VERSION=$(printf '%s' "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.componentVersion // "v1"')
KEYVAULT_NAME=$(printf '%s' "$SECRETS_JSON" | jq -r '
  .properties.status.resourceMetadata.dapr.metadata.vaultName
  // .properties.status.values.vaultName
  // .properties.status.resourceMetadata.keyVaultName
  // (
    .properties.status.outputResources[]?
    | select(.id | test("/Microsoft.KeyVault/vaults/[^/]+$"))
    | .id
    | split("/")[-1]
  )
  // empty
')

# Extract Entra auth details for Key Vault
KEYVAULT_TENANT_ID=$(printf '%s' "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureTenantId // .properties.status.values.azureTenantId // ""')
KEYVAULT_CLIENT_ID=$(printf '%s' "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureClientId // .properties.status.values.azureClientId // ""')
KEYVAULT_ENVIRONMENT=$(printf '%s' "$SECRETS_JSON" | jq -r '.properties.status.resourceMetadata.dapr.metadata.azureEnvironment // .properties.status.values.azureEnvironment // "AZUREPUBLICCLOUD"')

# Fall back to script parameters if not in recipe metadata
KEYVAULT_TENANT_ID=${KEYVAULT_TENANT_ID:-$TENANT_ID}
KEYVAULT_CLIENT_ID=${KEYVAULT_CLIENT_ID:-$CLIENT_ID}
SECRETS_METADATA_JSON=$(printf '%s' "$SECRETS_JSON" | jq -c '.properties.status.resourceMetadata.dapr.metadata // {}')
SECRETS_METADATA_JSON=$(set_metadata_default "$SECRETS_METADATA_JSON" "vaultName" "$KEYVAULT_NAME")
SECRETS_METADATA_JSON=$(set_metadata_default "$SECRETS_METADATA_JSON" "azureTenantId" "$KEYVAULT_TENANT_ID")
SECRETS_METADATA_JSON=$(set_metadata_default "$SECRETS_METADATA_JSON" "azureClientId" "$KEYVAULT_CLIENT_ID")
SECRETS_METADATA_JSON=$(set_metadata_default "$SECRETS_METADATA_JSON" "azureEnvironment" "$KEYVAULT_ENVIRONMENT")

# Validate extracted values
if [[ -z "$SERVICEBUS_NAMESPACE" ]]; then
  log_error "Failed to extract Service Bus namespace from $PUBSUB_RESOURCE_NAME resource. Check Radius recipe deployment."
  exit 1
fi

if [[ -z "$KEYVAULT_NAME" ]]; then
  log_error "Failed to extract Key Vault name from $SECRETS_RESOURCE_NAME resource. Check Radius recipe deployment."
  exit 1
fi

log_info "Extracted Azure resources:"
log_info "  Service Bus Namespace: $SERVICEBUS_NAMESPACE"
log_info "  Key Vault: $KEYVAULT_NAME"

# ── Generate Dapr Component manifests ─────────────────────────────────────────
TEMP_MANIFEST="${SCRIPT_DIR}/.apply-dapr-components-from-recipes.${$}.yaml"
trap 'rm -f "$TEMP_MANIFEST"' EXIT

# Build complete Dapr component manifest with proper variable substitution.
# Prefer recipe-advertised names, types, versions, and metadata, then fill only
# the backward-compatible gaps required by the current sample.
cat > "$TEMP_MANIFEST" <<EOF
---
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: $STATESTORE_COMPONENT_NAME
  namespace: $NAMESPACE
spec:
  type: $STATESTORE_TYPE
  version: $STATESTORE_COMPONENT_VERSION
  metadata:
EOF

render_metadata_yaml "$STATESTORE_METADATA_JSON" >> "$TEMP_MANIFEST"

# Pub/Sub component
cat >> "$TEMP_MANIFEST" <<EOF
---
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: $PUBSUB_COMPONENT_NAME
  namespace: $NAMESPACE
spec:
  type: $PUBSUB_COMPONENT_TYPE
  version: $PUBSUB_COMPONENT_VERSION
  metadata:
EOF

render_metadata_yaml "$PUBSUB_METADATA_JSON" >> "$TEMP_MANIFEST"
cat >> "$TEMP_MANIFEST" <<EOF
---
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: $SECRETS_COMPONENT_NAME
  namespace: $NAMESPACE
spec:
  type: $SECRETS_COMPONENT_TYPE
  version: $SECRETS_COMPONENT_VERSION
  metadata:
EOF
render_metadata_yaml "$SECRETS_METADATA_JSON" >> "$TEMP_MANIFEST"

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

#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PREREQUISITES: Azure Authentication Environment Variables
# ============================================================================
# This script requires Azure authentication credentials when registering
# Radius credentials for Azure provider integration. Radius uses these
# credentials to provision Azure resources (storage accounts, service bus,
# key vaults) via recipes.
#
# Required environment variables depend on your authentication mode:
#
# SERVICE PRINCIPAL MODE (--azure-auth-mode sp):
#   AZURE_CLIENT_ID       - Application (client) ID of the service principal
#   AZURE_CLIENT_SECRET   - Client secret for the service principal
#   AZURE_TENANT_ID       - Microsoft Entra tenant ID
#   AZURE_SUBSCRIPTION_ID - (Optional) Azure subscription ID; auto-detected if not set
#
# WORKLOAD IDENTITY MODE (--azure-auth-mode wi):
#   AZURE_CLIENT_ID       - Application (client) ID
#   AZURE_TENANT_ID       - Microsoft Entra tenant ID
#   AZURE_SUBSCRIPTION_ID - (Optional) Azure subscription ID; auto-detected if not set
#
# OPTIONAL FOR DATA-PLANE RBAC:
#   AZURE_PRINCIPAL_ID    - Microsoft Entra object ID of the principal
#                           (auto-resolved if not set; see --help for details)
#
# VALIDATION:
# The script validates these credentials early during preflight checks.
# If credentials are missing or invalid, you'll get a clear error with
# guidance on which variables to set.
#
# For more details, see docs/end-to-end-setup-walkthrough.md
# ============================================================================

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
RAD_BIN="${RAD_BIN:-rad}"
source "${SCRIPT_DIR}/lib/platform-common.sh"

default_image_tag() {
  git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "latest"
}

derive_default_container_registry() {
  local remote
  remote="$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)"

  if [[ "$remote" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    printf 'ghcr.io/%s/%s\n' \
      "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" \
      "$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
    return 0
  fi

  echo ""
}

APP_NAME="${DEFAULT_APP_NAME}"
ENV_NAME="${DEFAULT_ENV_NAME}"
GROUP_NAME="${DEFAULT_GROUP_NAME}"
WORKSPACE_NAME="${DEFAULT_WORKSPACE_NAME}"
KUBERNETES_NAMESPACE="radiusclaim-azure"
RESOURCE_GROUP=""
LOCATION="francecentral"
IMAGE_TAG="$(default_image_tag)"
RECIPE_TAG=""
CONTAINER_REGISTRY="$(derive_default_container_registry)"
RECIPE_REGISTRY=""
DEPLOYMENT_TARGET="radius"
IMAGE_PLATFORM=""
VALIDATION_URL=""
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
AZURE_AUTH_MODE="${AZURE_AUTH_MODE:-auto}"
SKIP_RECIPES=false
SKIP_IMAGE_PUSH=false
SKIP_VALIDATION=false
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-${DEFAULT_AKS_CLUSTER_NAME}}"
DRY_RUN=false
YES=false
SKIP_APP_DEPLOY=false
SKIP_COMPONENT_REFRESH=false
PG_ALLOW_AZURE_SERVICES=true
SHOULD_REGISTER_AZURE_CREDENTIAL=false
SHOULD_PUBLISH_RECIPES=false
CREATE_SPN=false
SETUP_WORKLOAD_IDENTITY=false
RESOURCE_GROUP_CREATED=false
PORT_FORWARD_PID=""
VALIDATION_BASE_URL=""
GHCR_PACKAGES_PRIVATE="${GHCR_PACKAGES_PRIVATE:-false}"
RANDOM_NAME_SUFFIX=""

usage() {
  cat <<USAGE
Usage: ./scripts/bootstrap.sh --resource-group <name> [options]

Orchestrates the repeatable RadiusClaim deployment path after the target
Kubernetes cluster is ready. Use ./scripts/prepare-cluster.sh first for
AKS/context/Dapr/Radius preparation on a new cluster.

Required:
  --resource-group <name>       Azure resource group for recipe-backed services

Optional:
  --location <region>           Azure region for the resource group/env (default: ${LOCATION})
  --app-name <name>             Radius application name (default: ${APP_NAME})
  --env-name <name>             Radius environment name (default: ${ENV_NAME})
  --workspace-name <name>       Radius workspace name (default: ${WORKSPACE_NAME})
  --group-name <name>           Radius group name (default: ${GROUP_NAME})
  --kubernetes-namespace <ns>   Radius environment namespace (default: ${KUBERNETES_NAMESPACE})
  --kube-context <context>      Kubernetes context for rad workspace create
  --container-registry <uri>    Container registry/repository prefix for app images
  --recipe-registry <uri>       OCI registry/repository prefix for Radius recipes
  --image-tag <tag>             Container image tag (default: current git SHA or latest)
  --recipe-tag <tag>            Radius recipe tag (default: same as --image-tag)
  --image-platform <platform>   Use docker buildx for a target platform (e.g. linux/amd64)
  --azure-auth-mode <mode>      Azure credential auth mode: auto, sp, or wi (default: ${AZURE_AUTH_MODE})
  --create-spn                  Create an Azure service principal for Radius (skipped if valid credentials exist)
  --setup-workload-identity     Enable OIDC issuer and workload identity on the AKS cluster (requires az CLI)
  --validation-url <url>        Explicit expense-api base URL for validation
  --skip-recipes                Skip recipe publishing even if artifacts look stale
  --skip-image-push             Skip Docker build/push for service images
  --skip-validation             Skip end-to-end validation
  --pg-no-allow-azure-services  Do not add the AllowAzureServices firewall rule to the PostgreSQL server (use private endpoint or VNet integration instead)
  --dry-run                     Print the planned mutations without executing them
  --yes                         Accept confirmation prompts non-interactively
  --help                        Show this help message

Required Azure auth env vars when bootstrap must register Radius credentials:
  Service principal mode: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID
  Workload identity mode: AZURE_CLIENT_ID, AZURE_TENANT_ID
Optional override for data-plane RBAC:
  AZURE_PRINCIPAL_ID (Microsoft Entra object ID for the client ID above)
Optional GHCR pull secret (required for private GHCR images on AKS):
  GHCR_USERNAME         GitHub username for the pull secret (e.g. wesback)
  GHCR_TOKEN            GitHub PAT with read:packages scope
  GHCR_PACKAGES_PRIVATE Set to "true" if GHCR packages are private (default: false)

Behavior note:
  For Azure-backed platform-secrets, bootstrap resolves the Key Vault from Radius
  metadata when available and otherwise uses the kvrc recipe naming contract. If the
  vault is soft-deleted and recoverable back into this deployment scope, bootstrap
  restores it; otherwise it fails early with actionable guidance.
USAGE
}

cleanup() {
  if [ -n "$PORT_FORWARD_PID" ]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --location)
      LOCATION="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --env-name)
      ENV_NAME="$2"
      shift 2
      ;;
    --workspace-name)
      WORKSPACE_NAME="$2"
      shift 2
      ;;
    --group-name)
      GROUP_NAME="$2"
      shift 2
      ;;
    --kubernetes-namespace|--namespace)
      KUBERNETES_NAMESPACE="$2"
      shift 2
      ;;
    --kube-context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --cluster-name)
      AKS_CLUSTER_NAME="$2"
      shift 2
      ;;
    --cluster-name=*)
      AKS_CLUSTER_NAME="${1#--cluster-name=}"
      shift
      ;;
    --aks-cluster-name)
      AKS_CLUSTER_NAME="$2"
      shift 2
      ;;
    --aks-cluster-name=*)
      AKS_CLUSTER_NAME="${1#--aks-cluster-name=}"
      shift
      ;;
    --container-registry)
      CONTAINER_REGISTRY="$2"
      shift 2
      ;;
    --recipe-registry)
      RECIPE_REGISTRY="$2"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --recipe-tag)
      RECIPE_TAG="$2"
      shift 2
      ;;
    --image-platform)
      IMAGE_PLATFORM="$2"
      shift 2
      ;;
    --azure-auth-mode)
      AZURE_AUTH_MODE="$2"
      shift 2
      ;;
    --validation-url)
      VALIDATION_URL="$2"
      shift 2
      ;;
    --skip-recipes)
      SKIP_RECIPES=true
      shift
      ;;
    --pg-no-allow-azure-services)
      PG_ALLOW_AZURE_SERVICES=false
      shift
      ;;
    --create-spn)
      CREATE_SPN=true
      shift
      ;;
    --setup-workload-identity)
      SETUP_WORKLOAD_IDENTITY=true
      shift
      ;;
    --skip-image-push)
      SKIP_IMAGE_PUSH=true
      shift
      ;;
    --skip-validation)
      SKIP_VALIDATION=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      YES=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown option: $1"
      ;;
  esac
done

[ -n "$RESOURCE_GROUP" ] || {
  usage >&2
  fail "--resource-group is required."
}

CONTAINER_REGISTRY="${CONTAINER_REGISTRY%/}"
[ -n "$CONTAINER_REGISTRY" ] || fail "Could not derive a container registry from remote.origin.url. Pass --container-registry explicitly."
if [ -z "$RECIPE_TAG" ]; then
  RECIPE_TAG="$IMAGE_TAG"
fi
if [ -z "$RECIPE_REGISTRY" ]; then
  RECIPE_REGISTRY="${CONTAINER_REGISTRY}/recipes"
fi
RECIPE_REGISTRY="${RECIPE_REGISTRY%/}"
WORKLOAD_NAMESPACE="${KUBERNETES_NAMESPACE}-${APP_NAME}"

ensure_kubectl_can_write() {
  kubectl auth can-i create deployments -n "$WORKLOAD_NAMESPACE" 2>/dev/null | grep -qx 'yes' \
    || fail "Current Kubernetes identity cannot create deployments in '${WORKLOAD_NAMESPACE}'."
  kubectl auth can-i create secrets -n "$WORKLOAD_NAMESPACE" 2>/dev/null | grep -qx 'yes' \
    || fail "Current Kubernetes identity cannot create secrets in '${WORKLOAD_NAMESPACE}'."
}

rad_env_exists() {
  "$RAD_BIN" env show "$ENV_NAME" >/dev/null 2>&1
}

rad_app_exists() {
  "$RAD_BIN" app show "$APP_NAME" >/dev/null 2>&1
}

fetch_env_namespace() {
  "$RAD_BIN" env show "$ENV_NAME" -o json 2>/dev/null \
    | sed -n '/^{/,$p' \
    | jq -r '.properties.compute.namespace // empty' 2>/dev/null || true
}

fetch_radius_app_resource_json() {
  local resource_type="$1"
  local resource_name="$2"

  "$RAD_BIN" resource show "$resource_type" "$resource_name" \
    --application "$APP_NAME" \
    --output json 2>/dev/null \
    | sed -n '/^{/,$p' || true
}

extract_first_output_resource_id() {
  local resource_json="$1"
  local resource_pattern="$2"

  printf '%s' "$resource_json" | jq -r --arg pattern "$resource_pattern" '
    [.properties.status.outputResources[]? | .id]
    | map(select(test($pattern)))
    | .[0] // empty
  ' 2>/dev/null || true
}

resolve_secret_store_key_vault_contract() {
  local secret_store_json
  local key_vault_id
  local key_vault_name
  local key_vault_uri
  local key_vault_resource_group
  local key_vault_subscription_id

  secret_store_json="$(fetch_radius_app_resource_json "Applications.Dapr/secretStores" "platform-secrets")"
  [ -n "$secret_store_json" ] || return 1

  key_vault_id="$(extract_first_output_resource_id "$secret_store_json" '/Microsoft.KeyVault/vaults/[^/]+$')"
  key_vault_name="$(printf '%s' "$secret_store_json" | jq -r '
    .properties.status.resourceMetadata.keyVaultName
    // .properties.status.values.vaultName
    // empty
  ' 2>/dev/null || true)"
  if [ -z "$key_vault_name" ] && [ -n "$key_vault_id" ]; then
    key_vault_name="${key_vault_id##*/}"
  fi

  key_vault_uri="$(printf '%s' "$secret_store_json" | jq -r '
    .properties.status.resourceMetadata.vaultUri
    // .properties.status.values.vaultUri
    // empty
  ' 2>/dev/null || true)"

  key_vault_resource_group="$(printf '%s' "$secret_store_json" | jq -r '
    .properties.status.resourceMetadata.resourceGroup
    // empty
  ' 2>/dev/null || true)"
  if [ -z "$key_vault_resource_group" ] && [ -n "$key_vault_id" ]; then
    key_vault_resource_group="$(extract_resource_group_from_resource_id "$key_vault_id")"
  fi

  key_vault_subscription_id=""
  if [ -n "$key_vault_id" ]; then
    key_vault_subscription_id="$(extract_subscription_from_resource_id "$key_vault_id")"
  fi

  [ -n "$key_vault_name" ] || [ -n "$key_vault_id" ] || return 1

  jq -nc \
    --arg vaultName "$key_vault_name" \
    --arg vaultId "$key_vault_id" \
    --arg vaultUri "$key_vault_uri" \
    --arg resourceGroup "$key_vault_resource_group" \
    --arg subscriptionId "$key_vault_subscription_id" \
    '{
      vaultName: $vaultName,
      vaultId: $vaultId,
      vaultUri: $vaultUri,
      resourceGroup: $resourceGroup,
      subscriptionId: $subscriptionId
    }'
}

discover_existing_kvrc_vault_name() {
  local kvrc_vaults
  local kvrc_vault_count

  kvrc_vaults="$(az keyvault list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'kvrc')].name" \
    -o tsv 2>/dev/null || true)"
  kvrc_vault_count="$(printf '%s\n' "$kvrc_vaults" | sed '/^$/d' | wc -l | tr -d ' ')"

  [ "$kvrc_vault_count" = "1" ] || return 1
  printf '%s\n' "$kvrc_vaults" | sed '/^$/d' | head -n 1
}

extract_kvrc_suffix_from_vault_name() {
  local vault_name="$1"

  if [[ "$vault_name" =~ ^kvrc(.+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

generate_random_name_suffix() {
  printf '%s\n' "$(date +%s | sha256sum | cut -c1-6)"
}

initialize_radius_resource_naming() {
  local secret_store_contract_json
  local existing_vault_name
  local existing_suffix

  RANDOM_NAME_SUFFIX=""
  if [ "$DEPLOYMENT_TARGET" != "radius" ]; then
    return 0
  fi

  secret_store_contract_json="$(resolve_secret_store_key_vault_contract || true)"
  existing_vault_name="$(printf '%s' "$secret_store_contract_json" | jq -r '.vaultName // empty' 2>/dev/null || true)"
  if [ -z "$existing_vault_name" ]; then
    existing_vault_name="$(discover_existing_kvrc_vault_name || true)"
  fi
  existing_suffix="$(extract_kvrc_suffix_from_vault_name "$existing_vault_name" || true)"

  if [ -n "$existing_suffix" ]; then
    RANDOM_NAME_SUFFIX="$existing_suffix"
    log_info "Reusing Radius resource naming suffix from existing Key Vault '${existing_vault_name}': ${RANDOM_NAME_SUFFIX}"
    return 0
  fi

  RANDOM_NAME_SUFFIX="$(generate_random_name_suffix)"
  log_info "Using new Radius resource naming suffix for this deployment: ${RANDOM_NAME_SUFFIX}"
}

resolve_secret_store_vault_name() {
  local secret_store_contract_json
  local secret_vault_name

  secret_store_contract_json="$(resolve_secret_store_key_vault_contract || true)"
  secret_vault_name="$(printf '%s' "$secret_store_contract_json" | jq -r '.vaultName // empty' 2>/dev/null || true)"
  if [ -z "$secret_vault_name" ]; then
    secret_vault_name="$(discover_existing_kvrc_vault_name || true)"
  fi
  if [ -n "$secret_vault_name" ]; then
    printf '%s\n' "$secret_vault_name"
    return 0
  fi

  if [ -n "$RANDOM_NAME_SUFFIX" ]; then
    printf 'kvrc%s\n' "$RANDOM_NAME_SUFFIX"
    return 0
  fi

  return 1
}

radius_azure_credential_registered() {
  "$RAD_BIN" credential list 2>/dev/null | grep -qi 'azure'
}

# Determine if a GHCR pull secret is needed based on registry type and privacy setting
needs_ghcr_pull_secret() {
  # Using ACR with managed identity — no pull secret needed
  if echo "${CONTAINER_REGISTRY:-}" | grep -q "azurecr.io"; then
    return 1
  fi
  
  # Using GHCR but packages are public — no pull secret needed
  if echo "${CONTAINER_REGISTRY:-}" | grep -q "ghcr.io"; then
    if [[ "${GHCR_PACKAGES_PRIVATE:-false}" != "true" ]]; then
      return 1
    fi
  fi
  
  # Private GHCR or other private registry — pull secret needed
  return 0
}

resolve_azure_auth_mode() {
  case "$AZURE_AUTH_MODE" in
    sp|wi)
      echo "$AZURE_AUTH_MODE"
      return 0
      ;;
    auto)
      if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_CLIENT_SECRET:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ]; then
        echo "sp"
      elif [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ]; then
        echo "wi"
      else
        echo ""
      fi
      return 0
      ;;
    *)
      fail "Unsupported --azure-auth-mode '$AZURE_AUTH_MODE'. Use auto, sp, or wi."
      ;;
  esac
}

log_auth_mode_explanation() {
  local mode="$1"
  
  case "$mode" in
    sp)
      log_info "Azure auth mode: Service Principal (sp)"
      log_info "  Detected: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID"
      log_info "  This mode uses a secret for authentication. Ensure the secret is securely rotated."
      log_info "  No cluster OIDC configuration required."
      ;;
    wi)
      log_info "Azure auth mode: Workload Identity (wi)"
      log_info "  Detected: AZURE_CLIENT_ID and AZURE_TENANT_ID (no AZURE_CLIENT_SECRET)"
      log_info "  This mode uses federated credentials — no secrets stored in the cluster."
      log_info "  Requires OIDC issuer and workload identity addons on the AKS cluster."
      log_info "  Bootstrap will auto-enable if not already configured (takes ~2 minutes)."
      ;;
    reuse-existing)
      log_info "Azure auth mode: Reusing existing Radius credential"
      log_info "  No new credential registration needed; workspace already has valid credentials."
      ;;
    *)
      log_warning "Azure auth mode unknown or not set."
      ;;
  esac
}

resolve_azure_principal_id() {
  # Explicit AZURE_PRINCIPAL_ID always wins
  if [ -n "${AZURE_PRINCIPAL_ID:-}" ]; then
    echo "${AZURE_PRINCIPAL_ID}"
    return 0
  fi

  # No AZURE_CLIENT_ID → cannot resolve
  if [ -z "${AZURE_CLIENT_ID:-}" ]; then
    echo >&2 "⚠️  Cannot resolve principal ID: AZURE_CLIENT_ID is not set."
    echo >&2 "    Set AZURE_PRINCIPAL_ID directly if using user identity or managed identity."
    echo ""
    return 0
  fi

  # Try to resolve via service principal lookup
  local resolved_id sp_err
  sp_err="$(mktemp "${REPO_ROOT}/.sp-lookup-err-XXXXXX")"
  resolved_id="$(az ad sp show --id "${AZURE_CLIENT_ID}" --query id -o tsv 2>"$sp_err" || true)"
  
  if [ -n "$resolved_id" ]; then
    rm -f "$sp_err"
    echo "$resolved_id"
    return 0
  fi

  # Service principal lookup failed — provide diagnostic with actual error
  echo >&2 "⚠️  Cannot resolve principal ID via service principal lookup."
  echo >&2 "    AZURE_CLIENT_ID is set to: ${AZURE_CLIENT_ID}"
  if [ -s "$sp_err" ]; then
    echo >&2 "    Azure CLI error: $(head -5 "$sp_err")"
  fi
  rm -f "$sp_err"
  echo >&2 ""
  echo >&2 "    Possible causes:"
  echo >&2 "    1. AZURE_CLIENT_ID points to an app registration without a service principal in this tenant"
  echo >&2 "    2. You are authenticated as a user identity instead of a service principal"
  echo >&2 "    3. Your Azure account lacks permission to query service principals"
  echo >&2 ""
  echo >&2 "    Resolution:"
  echo >&2 "    • For service principal auth: Verify the SP exists in your tenant:"
  echo >&2 "        az ad sp show --id \"\$AZURE_CLIENT_ID\""
  echo >&2 "    • For user identity or managed identity: Set AZURE_PRINCIPAL_ID manually:"
  echo >&2 "        export AZURE_PRINCIPAL_ID=\$(az ad signed-in-user show --query id -o tsv)"
  echo >&2 "    • For workload identity: Provide the managed identity's principal object ID"
  echo ""
  return 0
}

resolve_auth_context() {
  # Consolidates principal ID resolution with subscription/tenant validation.
  # This is the single source of truth for auth context setup — validates
  # that the current Azure CLI context (subscription + tenant) matches the
  # target and resolves the principal object ID for RBAC operations.
  #
  # Returns: principal_id (or empty if unresolvable)
  # Side effects: Validates subscription/tenant match; dies on mismatch
  
  local principal_id
  local current_sub current_tenant target_sub target_tenant
  
  # Get current Azure CLI context
  current_sub="$(az account show --query id -o tsv 2>/dev/null || true)"
  current_tenant="$(az account show --query tenantId -o tsv 2>/dev/null || true)"
  
  # Determine target subscription/tenant
  # If AZURE_TENANT_ID is set (from SP creation or env), use it; otherwise use current
  target_tenant="${AZURE_TENANT_ID:-$current_tenant}"
  target_sub="${AZURE_SUBSCRIPTION_ID:-$current_sub}"
  
  # Validate subscription and tenant match — catches context switches
  if [ -n "$current_sub" ] && [ -n "$target_sub" ] && [ "$current_sub" != "$target_sub" ]; then
    die "ERROR: Current Azure CLI subscription ($current_sub) does not match target subscription ($target_sub).
Please switch to the correct subscription and re-run:
  az account set --subscription $target_sub"
  fi
  
  if [ -n "$current_tenant" ] && [ -n "$target_tenant" ] && [ "$current_tenant" != "$target_tenant" ]; then
    die "ERROR: Current Azure CLI tenant ($current_tenant) does not match target tenant ($target_tenant).
You may need to use 'az login' with the correct tenant or export AZURE_TENANT_ID explicitly."
  fi
  
  # Resolve principal ID (may return empty if unable to resolve)
  principal_id="$(resolve_azure_principal_id)"
  echo "$principal_id"
}

current_secret_store_recipe_name() {
  jq -r '.parameters.daprBackings.defaultValue.secretStore.recipeName // empty' "$REPO_ROOT/infra/radius/app.json" 2>/dev/null || true
}

check_recipe_artifact_access() {
  local artifact_name="$1"
  docker manifest inspect "${RECIPE_REGISTRY}/${artifact_name}:${RECIPE_TAG}" >/dev/null 2>&1
}

# Test if a recipe OCI artifact is accessible WITHOUT credentials (anonymous access).
# This mirrors what the Radius operator sees: it runs in radius-system with no Docker
# login, so private packages cause a 401 at deploy time even if the user can pull them.
check_recipe_anonymous_access() {
  local artifact_name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  printf '{}' > "$tmpdir/config.json"
  local result=0
  DOCKER_CONFIG="$tmpdir" docker manifest inspect "${RECIPE_REGISTRY}/${artifact_name}:${RECIPE_TAG}" >/dev/null 2>&1 || result=$?
  rm -rf "$tmpdir"
  return $result
}

# Verify that all recipe OCI artifacts are publicly accessible (no credentials needed).
# Radius's applications-rp operator pulls Bicep recipe artifacts using the ORAS Go library,
# which runs inside the Kubernetes pod with no Docker credentials. Private GHCR packages
# therefore always result in a 401 at deploy time — there is no supported Helm value or
# rad CLI flag to supply OCI credentials to the operator.
#
# The correct solution for a demo/development project is to make the GHCR recipe packages
# public. Recipe artifacts contain only Bicep templates — no secrets or credentials.
# See docs/adr/ghcr-recipe-packages-public.md for the full rationale.
#
# GitHub does NOT provide a REST API to change container package visibility; it must be
# done once via the GitHub web UI per-package.
require_public_recipe_access() {
  if [ "${DRY_RUN:-false}" = true ]; then
    log_info "Dry run — skipping OCI artifact public-access check."
    return 0
  fi

  local private_packages=()
  for artifact in state-store pubsub secrets; do
    if ! check_recipe_anonymous_access "$artifact"; then
      private_packages+=("$artifact")
    fi
  done

  if [ ${#private_packages[@]} -eq 0 ]; then
    log_success "  ✓ All recipe OCI artifacts are publicly accessible."
    return 0
  fi

  # Extract owner from registry path, e.g. ghcr.io/wesback/radiusclaim/recipes → wesback
  local registry_owner
  registry_owner=$(echo "${RECIPE_REGISTRY}" | cut -d'/' -f2)

  log_error "The following recipe OCI packages are private and Radius cannot pull them:"
  for artifact in "${private_packages[@]}"; do
    log_error "  • ${RECIPE_REGISTRY}/${artifact}:${RECIPE_TAG}"
  done
  log_error ""
  log_error "Recipe packages must be public. They contain only Bicep templates — no secrets."
  log_error "Make them public once via the GitHub web UI (Settings → Change visibility → Public):"
  log_error ""
  for artifact in "${private_packages[@]}"; do
    local pkg_path
    pkg_path=$(echo "${RECIPE_REGISTRY#*/}" | sed "s|/|%2F|g")
    pkg_path="${pkg_path}%2F${artifact}"
    log_error "  https://github.com/users/${registry_owner}/packages/container/${pkg_path}/settings"
  done
  log_error ""
  log_error "After making the packages public, re-run bootstrap."

  fail "Recipe OCI artifacts are private. Make them public in the GitHub web UI (URLs above) and re-run."
}

lookup_deleted_key_vault() {
  local vault_name="$1"
  local deleted_vaults_json

  deleted_vaults_json="$(az keyvault list-deleted -o json 2>/dev/null)" || return 1
  printf '%s' "$deleted_vaults_json" | jq -c --arg name "$vault_name" 'map(select(.name == $name)) | first // empty'
}

extract_resource_group_from_resource_id() {
  local resource_id="$1"
  printf '%s\n' "$resource_id" | sed -n 's|.*/resourceGroups/\([^/]*\)/.*|\1|p'
}

extract_subscription_from_resource_id() {
  local resource_id="$1"
  printf '%s\n' "$resource_id" | sed -n 's|/subscriptions/\([^/]*\)/.*|\1|p'
}

wait_for_namespace() {
  local namespace="$1"
  local attempt

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  for attempt in $(seq 1 30); do
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  fail "Timed out waiting for namespace '${namespace}'."
}

wait_for_key_vault_recovery() {
  local vault_name="$1"
  local resource_group="${2:-$RESOURCE_GROUP}"
  local attempt

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  for attempt in $(seq 1 30); do
    if az keyvault show --name "$vault_name" --resource-group "$resource_group" --query name -o tsv >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done

  fail "Timed out waiting for restored Key Vault '${vault_name}' in resource group '${resource_group}'."
}

ensure_azure_secret_store_ready() {
  local secret_store_recipe
  local secret_store_contract_json
  local secret_vault_name
  local secret_vault_id
  local secret_vault_resource_group
  local secret_vault_source
  local deleted_vault_json
  local deleted_vault_id
  local deleted_resource_group
  local deleted_subscription_id
  local deleted_location
  local deleted_purge_date
  local normalized_deleted_location
  local normalized_target_location
  local restore_message
  local scope_mismatch_message

  secret_store_recipe="$(current_secret_store_recipe_name)"
  [ "$secret_store_recipe" = "azure-keyvault-secrets" ] || return 0

  secret_store_contract_json="$(resolve_secret_store_key_vault_contract || true)"
  secret_vault_name="$(printf '%s' "$secret_store_contract_json" | jq -r '.vaultName // empty' 2>/dev/null || true)"
  secret_vault_id="$(printf '%s' "$secret_store_contract_json" | jq -r '.vaultId // empty' 2>/dev/null || true)"
  secret_vault_resource_group="$(printf '%s' "$secret_store_contract_json" | jq -r '.resourceGroup // empty' 2>/dev/null || true)"

  if [ -n "$secret_vault_name" ]; then
    secret_vault_source="Radius resource metadata"
  else
    secret_vault_name="$(resolve_secret_store_vault_name | tr -d '\r' || true)"
    secret_vault_source="kvrc recipe contract"
  fi

  [ -n "$secret_vault_name" ] || fail "Could not resolve the Key Vault name for 'platform-secrets' from Radius metadata or the kvrc recipe contract."
  [ -n "$secret_vault_resource_group" ] || secret_vault_resource_group="$RESOURCE_GROUP"

  section "Preflighting Azure-backed secret store"
  log_info "platform-secrets maps to Key Vault '${secret_vault_name}' (${secret_vault_source})."

  if az keyvault show --name "$secret_vault_name" --resource-group "$secret_vault_resource_group" --query name -o tsv >/dev/null 2>&1; then
    log_success "Key Vault '${secret_vault_name}' already exists in '${secret_vault_resource_group}'."
    return 0
  fi

  deleted_vault_json="$(lookup_deleted_key_vault "$secret_vault_name")" \
    || fail "Could not inspect soft-deleted Key Vaults for '${secret_vault_name}'. Ensure the current Azure identity can run 'az keyvault list-deleted', or recover/purge the vault manually before retrying."

  [ -n "$deleted_vault_json" ] || return 0

  deleted_vault_id="$(printf '%s' "$deleted_vault_json" | jq -r '.properties.vaultId // empty')"
  deleted_resource_group="$(extract_resource_group_from_resource_id "$deleted_vault_id")"
  deleted_subscription_id="$(extract_subscription_from_resource_id "$deleted_vault_id")"
  deleted_location="$(printf '%s' "$deleted_vault_json" | jq -r '.properties.location // empty')"
  deleted_purge_date="$(printf '%s' "$deleted_vault_json" | jq -r '.properties.scheduledPurgeDate // empty')"
  normalized_deleted_location="$(printf '%s' "$deleted_location" | tr '[:upper:]' '[:lower:]')"
  normalized_target_location="$(printf '%s' "$LOCATION" | tr '[:upper:]' '[:lower:]')"

  if [ -n "$secret_vault_id" ] && [ -n "$deleted_vault_id" ] && [ "$secret_vault_id" != "$deleted_vault_id" ]; then
    fail "Key Vault '${secret_vault_name}' is soft-deleted, but Radius metadata expects '${secret_vault_id}' and Azure reports '${deleted_vault_id}'. Resolve the mismatch before retrying."
  fi

  if [ -z "$deleted_resource_group" ] || [ -z "$deleted_subscription_id" ] || [ -z "$deleted_location" ] \
    || [ "$deleted_resource_group" != "$RESOURCE_GROUP" ] \
    || [ "$deleted_subscription_id" != "$AZURE_SUBSCRIPTION_ID" ] \
    || [ "$normalized_deleted_location" != "$normalized_target_location" ]; then
    scope_mismatch_message="Key Vault '${secret_vault_name}' is soft-deleted, but Azure can only recover it back into subscription '${deleted_subscription_id:-unknown}', resource group '${deleted_resource_group:-unknown}', location '${deleted_location:-unknown}'. Bootstrap targets subscription '${AZURE_SUBSCRIPTION_ID}', resource group '${RESOURCE_GROUP}', location '${LOCATION}', so Radius cannot safely reuse that deleted vault."
    if [ -n "$deleted_purge_date" ]; then
      scope_mismatch_message="${scope_mismatch_message} Scheduled purge: ${deleted_purge_date}."
    fi
    fail "${scope_mismatch_message} Restore or purge the deleted vault manually, or use a different Radius environment name before retrying."
  fi

  restore_message="Key Vault '${secret_vault_name}' is currently soft-deleted in '${secret_vault_resource_group}'"
  if [ -n "$deleted_purge_date" ]; then
    restore_message="${restore_message} (scheduled purge: ${deleted_purge_date})"
  fi
  restore_message="${restore_message}. Restore it now so bootstrap can reuse the Azure-backed secret store"

  if ! prompt_confirm "$restore_message"; then
    fail "Bootstrap cannot continue until the deleted Key Vault '${secret_vault_name}' is restored, purged, or the Radius environment name changes."
  fi

  section "Recovering soft-deleted Key Vault"
  run_cmd az keyvault recover --name "$secret_vault_name" --location "$deleted_location" --output none
  wait_for_key_vault_recovery "$secret_vault_name" "$secret_vault_resource_group"
  log_success "Restored Key Vault '${secret_vault_name}' for platform-secrets reuse."
}

wait_for_deployment() {
  local deployment="$1"
  local attempt

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  for attempt in $(seq 1 30); do
    if kubectl get deployment "$deployment" -n "$WORKLOAD_NAMESPACE" >/dev/null 2>&1; then
      kubectl rollout status "deployment/${deployment}" -n "$WORKLOAD_NAMESPACE" --timeout=5m
      return 0
    fi
    sleep 10
  done

  fail "Timed out waiting for deployment '${deployment}' in '${WORKLOAD_NAMESPACE}'."
}

verify_components_present() {
  local components_json

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  components_json="$(kubectl get components -n "$WORKLOAD_NAMESPACE" -o json 2>/dev/null)"
  printf '%s' "$components_json" | jq -e '[.items[].metadata.name] | contains(["statestore", "pubsub", "platform-secrets"])' >/dev/null \
    || fail "Expected Dapr components statestore, pubsub, and platform-secrets in '${WORKLOAD_NAMESPACE}'."
}

wait_for_sidecar_log() {
  local deployment="$1"
  local needle="$2"
  local attempt

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  for attempt in $(seq 1 12); do
    if kubectl logs -n "$WORKLOAD_NAMESPACE" "deployment/${deployment}" -c daprd --tail=200 2>/dev/null | grep -Fq "$needle"; then
      return 0
    fi
    sleep 5
  done

  # Diagnostic: show what pods exist and their labels to help debug false negatives.
  # Radius-managed pods use app.kubernetes.io/name=<name>, NOT app=<name>.
  log_warning "Sidecar check failed for '${deployment}'. Dumping diagnostics…"
  log_warning "Pods in namespace:"
  kubectl get pods -n "$WORKLOAD_NAMESPACE" -o wide 2>&1 | while IFS= read -r line; do log_warning "  $line"; done
  log_warning "Last 10 daprd log lines (deployment/${deployment}):"
  kubectl logs -n "$WORKLOAD_NAMESPACE" "deployment/${deployment}" -c daprd --tail=10 2>&1 | while IFS= read -r line; do log_warning "  $line"; done

  fail "Dapr sidecar for '${deployment}' did not report '${needle}'. Verify with: kubectl logs -n ${WORKLOAD_NAMESPACE} deployment/${deployment} -c daprd --tail=30 | grep -F '${needle}'"
}

# Patch the default service account in the workload namespace so Kubernetes uses
# ghcr-pull-secret for every pod — including those Radius spawns after deploy.
# This is idempotent: safe to run on every bootstrap and on re-deploys.
# Skipped when pull secret is not needed (public GHCR, ACR with managed identity).
patch_pull_secret_to_serviceaccount() {
  local namespace="$1"

  # Skip if pull secret is not needed
  if ! needs_ghcr_pull_secret; then
    return 0
  fi

  if [ -z "${GHCR_TOKEN:-}" ] || [ -z "${GHCR_USERNAME:-}" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    log_info "[dry-run] Would patch default service account in '${namespace}' with ghcr-pull-secret."
    return 0
  fi

  # Radius may recreate the namespace on re-deploy, clearing any pre-deploy secrets.
  # Re-create the secret here (post-deploy) to guarantee it exists before patching SA.
  if ! kubectl get secret ghcr-pull-secret -n "$namespace" >/dev/null 2>&1; then
    log_info "Re-creating ghcr-pull-secret in '${namespace}' (cleared by Radius namespace lifecycle)."
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${GHCR_USERNAME}" \
      --docker-password="${GHCR_TOKEN}" \
      -n "$namespace" >/dev/null
  fi

  # Patch is a merge — if imagePullSecrets already contains the entry, kubectl is a no-op.
  local current
  current="$(kubectl get sa default -n "$namespace" -o jsonpath='{.imagePullSecrets}' 2>/dev/null || echo '')"
  if echo "$current" | grep -q "ghcr-pull-secret"; then
    echo "  ✓ default service account in '${namespace}' already has ghcr-pull-secret"
  else
    kubectl patch serviceaccount default -n "$namespace" \
      --patch '{"imagePullSecrets":[{"name":"ghcr-pull-secret"}]}' >/dev/null
    echo "  ✓ Patched default service account in '${namespace}' with imagePullSecrets: ghcr-pull-secret"
  fi

  # Evict pods stuck in ImagePullBackOff — they won't self-heal once the SA is patched
  # unless they are rescheduled.  Deletion triggers immediate recreation.
  local stuck_pods
  stuck_pods="$(kubectl get pods -n "$namespace" -o json 2>/dev/null \
    | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "ImagePullBackOff") | .metadata.name' \
    || true)"
  if [ -n "$stuck_pods" ]; then
    echo "  Deleting ImagePullBackOff pods so they restart with updated credentials:"
    echo "$stuck_pods" | xargs kubectl delete pod -n "$namespace" --ignore-not-found >/dev/null
    echo "  ✓ Stuck pods deleted"
  else
    echo "  ✓ No ImagePullBackOff pods found in '${namespace}'"
  fi
}

# ---------------------------------------------------------------------------
# Radius stuck-state recovery
# ---------------------------------------------------------------------------
# When a previous `rad deploy` times out or is interrupted, Radius may leave
# container resources in "Updating" (or other in-progress) provisioning states.
# A subsequent deploy is rejected with HTTP 409 Conflict:
#   "The target resource is in progress state: Updating."
# This function detects those stuck resources and deletes them so the next
# deploy can recreate them cleanly.
cleanup_stuck_radius_resources() {
  local app_name="$1"
  local group_name="$2"
  local workspace_name="$3"

  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Would check for stuck Radius container resources in group '${group_name}'"
    return 0
  fi

  local resource_json
  resource_json="$("$RAD_BIN" resource list Applications.Core/containers \
    -g "$group_name" -w "$workspace_name" -o json 2>/dev/null || true)"

  # If we can't list resources (group doesn't exist, no app yet), nothing to clean.
  if [ -z "$resource_json" ]; then
    return 0
  fi

  # Extract valid JSON (rad CLI sometimes prefixes non-JSON output).
  resource_json="$(echo "$resource_json" | sed -n '/^\[/,$p')"
  if [ -z "$resource_json" ] || ! echo "$resource_json" | jq empty 2>/dev/null; then
    return 0
  fi

  # Find containers whose provisioningState is NOT Succeeded (covers Updating,
  # Failed, Deleting, or any other non-terminal state).
  local stuck_resources
  stuck_resources="$(echo "$resource_json" \
    | jq -r '.[] | select(.properties.status.outputResources != null) | select(.properties.provisioningState != "Succeeded") | .name // empty' 2>/dev/null || true)"

  if [ -z "$stuck_resources" ]; then
    return 0
  fi

  log_warning "Detected Radius container resources in non-ready state — cleaning up before redeploy..."
  local resource_name
  while IFS= read -r resource_name; do
    [ -n "$resource_name" ] || continue
    local state
    state="$(echo "$resource_json" \
      | jq -r --arg n "$resource_name" '.[] | select(.name == $n) | .properties.provisioningState // "unknown"' 2>/dev/null || echo "unknown")"
    log_info "  Deleting stuck container '${resource_name}' (state: ${state})"
    "$RAD_BIN" resource delete Applications.Core/containers "${resource_name}" \
      -g "$group_name" -w "$workspace_name" --yes 2>/dev/null || true
  done <<< "$stuck_resources"

  log_success "Stuck resources cleared — rad deploy can proceed."
}

# Returns success when the named Dapr resource no longer appears in
# `rad resource list`; otherwise returns non-zero after the poll window.
# Args: resource_type resource_name group_name workspace_name max_attempts poll_interval
wait_for_dapr_resource_deletion() {
  local resource_type="$1"
  local resource_name="$2"
  local group_name="$3"
  local workspace_name="$4"
  local max_attempts="$5"
  local poll_interval="$6"
  local friendly_type="${7:-$(basename "$resource_type")}"
  local attempt=0
  local list_json
  local still_present

  while [ "$attempt" -lt "$max_attempts" ]; do
    list_json="$( "$RAD_BIN" resource list "$resource_type" \
      -g "$group_name" -w "$workspace_name" -o json 2>/dev/null || true )"
    list_json="$(echo "$list_json" | sed -n '/^\[/,$p')"

    if [ -z "$list_json" ] || ! echo "$list_json" | jq empty 2>/dev/null; then
      return 0
    fi

    still_present="$(echo "$list_json" \
      | jq -r --arg n "$resource_name" '.[] | select(.name == $n) | .name' 2>/dev/null \
      || true)"

    if [ -z "$still_present" ]; then
      return 0
    fi

    attempt=$(( attempt + 1 ))
    if [ "$attempt" -lt "$max_attempts" ]; then
      log_info "  Waiting for ${friendly_type} '${resource_name}' deletion... (${attempt}/${max_attempts})"
      sleep "$poll_interval"
    fi
  done

  return 1
}

radius_controllers_healthy() {
  local deployment
  for deployment in ucp applications-rp controller; do
    if ! kubectl rollout status "deployment/${deployment}" -n radius-system --timeout=5s >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

force_remove_dapr_component_finalizers() {
  local component_name="$1"
  local component_namespace="$2"
  local component_json
  local deletion_timestamp
  local finalizer_count

  component_json="$(kubectl get components.dapr.io "$component_name" \
    -n "$component_namespace" -o json 2>/dev/null || true)"
  if [ -z "$component_json" ] || ! echo "$component_json" | jq empty 2>/dev/null; then
    return 1
  fi

  deletion_timestamp="$(echo "$component_json" | jq -r '.metadata.deletionTimestamp // empty' 2>/dev/null || true)"
  finalizer_count="$(echo "$component_json" | jq -r '(.metadata.finalizers // []) | length' 2>/dev/null || echo "0")"

  if [ -z "$deletion_timestamp" ] || [ "${finalizer_count}" = "0" ]; then
    return 1
  fi

  log_warning "Dapr component '${component_name}' is stuck with finalizers in namespace '${component_namespace}' — force-removing finalizers."
  kubectl patch components.dapr.io "$component_name" -n "$component_namespace" \
    --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null 2>&1 || true
  return 0
}

# Deletes a Dapr component resource via `rad resource delete`, surfaces Radius
# UCP diagnostics, verifies deletion, and escalates common stuck-state failure
# modes with actionable guidance.
#
# Args: resource_type resource_name group_name workspace_name
delete_dapr_resource_with_verify() {
  local resource_type="$1"
  local resource_name="$2"
  local group_name="$3"
  local workspace_name="$4"
  local friendly_type
  local resource_json
  local resource_env
  local resource_env_name
  local provisioning_state
  local initial_wait_attempts=6
  local final_wait_attempts=3
  local poll_interval=10
  local fallback_taken=false
  local component_present=false
  friendly_type="$(basename "$resource_type")"

  # Issue the delete.  Redirect: 2>&1 1>/dev/null captures stderr into the
  # variable (preserving it for diagnostic logging) while discarding stdout.
  # || true prevents set -e from aborting on a non-zero exit code.
  local delete_stderr
  delete_stderr="$( "$RAD_BIN" resource delete "$resource_type" "$resource_name" \
    -g "$group_name" -w "$workspace_name" --yes 2>&1 1>/dev/null )" || true
  if [ -n "$delete_stderr" ]; then
    log_info "  rad resource delete ${friendly_type}/${resource_name}: ${delete_stderr}"
  fi

  if wait_for_dapr_resource_deletion \
    "$resource_type" "$resource_name" "$group_name" "$workspace_name" \
    "$initial_wait_attempts" "$poll_interval" "$friendly_type"; then
    log_info "Stale ${friendly_type} '${resource_name}' removed."
    return 0
  fi

  log_warning "${friendly_type} '${resource_name}' still present after $(( initial_wait_attempts * poll_interval ))s — investigating stuck delete."

  if ! radius_controllers_healthy; then
    log_error "Radius controllers are not healthy; restart 'ucp', 'applications-rp', and 'controller' in namespace 'radius-system' before rerunning bootstrap."
  fi

  resource_json="$( "$RAD_BIN" resource show "$resource_type" "$resource_name" \
    -g "$group_name" -w "$workspace_name" -o json 2>/dev/null | sed -n '/^{/,$p' || true )"
  if [ -n "$resource_json" ] && echo "$resource_json" | jq empty 2>/dev/null; then
    provisioning_state="$(echo "$resource_json" | jq -r '.properties.provisioningState // empty' 2>/dev/null || true)"
    resource_env="$(echo "$resource_json" | jq -r '.properties.environment // empty' 2>/dev/null || true)"
    resource_env_name="${resource_env##*/}"
  else
    provisioning_state=""
    resource_env=""
    resource_env_name=""
  fi

  if kubectl get components.dapr.io "$resource_name" -n "$KUBERNETES_NAMESPACE" >/dev/null 2>&1; then
    component_present=true
    if force_remove_dapr_component_finalizers "$resource_name" "$KUBERNETES_NAMESPACE"; then
      fallback_taken=true
    fi
  fi

  if [ "$fallback_taken" = true ]; then
    log_info "Re-checking ${friendly_type} '${resource_name}' after fallback cleanup..."
  else
    log_info "Re-checking ${friendly_type} '${resource_name}' after diagnostic pause..."
  fi

  if wait_for_dapr_resource_deletion \
    "$resource_type" "$resource_name" "$group_name" "$workspace_name" \
    "$final_wait_attempts" "$poll_interval" "$friendly_type"; then
    log_info "Stale ${friendly_type} '${resource_name}' removed."
    return 0
  fi

  if [ "$component_present" = false ] \
    && [ -n "$resource_env_name" ] \
    && ! "$RAD_BIN" env show "$resource_env_name" >/dev/null 2>&1; then
    log_error "${friendly_type} '${resource_name}' is stuck in Radius control-plane state (provisioningState='${provisioning_state:-unknown}', missing environment '${resource_env_name}', no Dapr component projected in namespace '${KUBERNETES_NAMESPACE}'). Restart Radius controllers with 'kubectl rollout restart deployment/ucp deployment/applications-rp deployment/controller -n radius-system'; if it still persists, reinstall Radius ('rad uninstall kubernetes && rad install kubernetes') and rerun bootstrap."
    return 1
  fi

  if [ "$component_present" = true ]; then
    log_error "${friendly_type} '${resource_name}' still exists after cleanup attempts. Run: kubectl delete components.dapr.io ${resource_name} -n ${KUBERNETES_NAMESPACE} --force --grace-period=0"
    return 1
  fi

  log_error "${friendly_type} '${resource_name}' still exists after cleanup attempts. Radius UCP accepted the delete but never completed it. Restart Radius controllers with 'kubectl rollout restart deployment/ucp deployment/applications-rp deployment/controller -n radius-system' and, if the resource remains, reinstall Radius with 'rad uninstall kubernetes && rad install kubernetes' before rerunning bootstrap."
  return 1
}

# Wraps `rad deploy` with automatic recovery from known transient and persistent errors.
# Handles:
#   1. "context deadline exceeded" (Kubernetes client rate limiter timeout) — retries with exponential backoff
#   2. "in progress state" (stuck Radius resources) — cleans up and retries
#   3. "different application and/or environment" (stale application/Dapr binding) — deletes and retries
# 
# The "context deadline exceeded" error is transient: AKS API may be slow/overloaded during Radius's
# status polling, but pods often finish deploying normally. Exponential backoff lets the AKS API
# recover between retry attempts, improving success rate.
rad_deploy_with_recovery() {
  local deploy_output
  local deploy_rc=0
  local retry_count=0
  local max_retries=3
  local backoff_seconds=5

  if [ "$DRY_RUN" = true ]; then
    run_cmd "$RAD_BIN" "$@"
    return $?
  fi

  # Retry loop for transient errors.
  while [ "$retry_count" -le "$max_retries" ]; do
    deploy_output="$("$RAD_BIN" "$@" 2>&1)" && deploy_rc=0 || deploy_rc=$?

    if [ "$deploy_rc" -eq 0 ]; then
      # Print captured output so section log stays consistent.
      [ -n "$deploy_output" ] && echo "$deploy_output"
      return 0
    fi

    # Check if this is the Kubernetes client rate limiter timeout (transient).
    if echo "$deploy_output" | grep -q "context deadline exceeded\|rate limiter Wait returned an error"; then
      if [ "$retry_count" -lt "$max_retries" ]; then
        log_warning "rad deploy timed out (Kubernetes client rate limiter deadline exceeded). Attempt $((retry_count + 1))/$max_retries."
        log_info "Waiting ${backoff_seconds}s before retry (exponential backoff)..."
        sleep "$backoff_seconds"
        backoff_seconds=$((backoff_seconds * 2))
        retry_count=$((retry_count + 1))
        continue
      else
        log_error "rad deploy timed out after $max_retries retries. AKS API may be overloaded or experiencing issues."
        echo "$deploy_output" >&2
        return "$deploy_rc"
      fi
    fi

    # Check if this is the known stuck-state conflict.
    if echo "$deploy_output" | grep -q "in progress state"; then
      log_warning "rad deploy failed due to stuck Radius resources (Conflict: in progress state)."
      log_info "Attempting automatic recovery..."

      cleanup_stuck_radius_resources "$APP_NAME" "$GROUP_NAME" "$WORKSPACE_NAME"

      log_info "Retrying rad deploy..."
      "$RAD_BIN" "$@"
      return $?
    fi

    # Check if this is a stale application bound to a different environment.
    if echo "$deploy_output" | grep -q "different application and/or environment"; then
      log_warning "rad deploy failed due to stale application or Dapr component bound to a different environment (BadRequest: different application and/or environment)."
      log_info "Attempting automatic recovery..."

      # Extract resource name from error message (e.g., "resource 'platform-secrets'")
      _failed_resource="$(echo "$deploy_output" | grep -o "resource '[^']*'" | head -1 | sed "s/resource '//;s/'//")"
      
      if [ -n "$_failed_resource" ]; then
        log_info "  Detected stale resource: '${_failed_resource}'"
        
        # Try deleting as application
        "$RAD_BIN" app delete "${_failed_resource}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        "$RAD_BIN" resource delete Applications.Core/applications "${_failed_resource}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        
        # Try deleting as Dapr secretStore
        "$RAD_BIN" resource delete Applications.Dapr/secretStores "${_failed_resource}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        
        # Try deleting as Dapr stateStore
        "$RAD_BIN" resource delete Applications.Dapr/stateStores "${_failed_resource}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        
        # Try deleting as Dapr pubSubBroker
        "$RAD_BIN" resource delete Applications.Dapr/pubSubBrokers "${_failed_resource}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        
        log_info "Stale resource '${_failed_resource}' cleanup attempted."
      else
        # Fallback to deleting just the application
        log_info "  Deleting stale application '${APP_NAME}'"
        "$RAD_BIN" app delete "${APP_NAME}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        "$RAD_BIN" resource delete Applications.Core/applications "${APP_NAME}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      fi
      
      unset _failed_resource

      log_info "Retrying rad deploy..."
      "$RAD_BIN" "$@"
      return $?
    fi

    # Not a known recoverable error — surface the original failure.
    echo "$deploy_output" >&2
    return "$deploy_rc"
  done

  # Unreachable, but satisfy shellcheck
  return "$deploy_rc"
}

# REMOVED: get_recipe_resource_metadata()
# This function extracted resourceMetadata for a dedicated RBAC helper. Bootstrap now resolves
# recipe-created resource identities inline from Radius status metadata/outputResources where the
# RBAC operations actually run, so the standalone helper is no longer needed.

# REMOVED: assign_managed_identity_rbac_on_recipe_resources()
# Radius v0.56 still requires post-deployment RBAC for some recipe-created Azure resources.
# Those role assignments now happen inline in bootstrap using the actual resource IDs resolved
# from Radius state rather than a separate helper with duplicated discovery logic.


build_and_push_service() {
  local service_name="$1"
  local dockerfile_path="$2"
  local image_ref="${CONTAINER_REGISTRY}/${service_name}:${IMAGE_TAG}"

  # Auto-detect platform mismatch: if IMAGE_PLATFORM is not set, check whether
  # the local build host arch differs from the cluster node arch. AKS always runs
  # linux/amd64; building on Apple Silicon (arm64) without --platform produces an
  # arm64 image that AKS nodes cannot run ("no match for platform in manifest").
  local effective_platform="$IMAGE_PLATFORM"
  if [ -z "$effective_platform" ]; then
    local host_arch cluster_arch
    host_arch="$(uname -m)"
    cluster_arch="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}' 2>/dev/null || true)"
    if [ "$host_arch" = "arm64" ] && [ "$cluster_arch" = "amd64" ]; then
      effective_platform="linux/amd64"
      log_info "Auto-detected platform mismatch (host: arm64, cluster: amd64). Building for linux/amd64."
    fi
  fi

  if [ -n "$effective_platform" ]; then
    run_cmd docker buildx build \
      --file "$dockerfile_path" \
      --platform "$effective_platform" \
      --tag "$image_ref" \
      --push \
      "$REPO_ROOT"
  else
    run_cmd docker build \
      --file "$dockerfile_path" \
      --tag "$image_ref" \
      "$REPO_ROOT"
    run_cmd docker push "$image_ref"
  fi
}

normalize_url() {
  case "$1" in
    http://*|https://*)
      printf '%s\n' "${1%/}"
      ;;
    *)
      printf 'http://%s\n' "${1%/}"
      ;;
  esac
}

get_gateway_url() {
  local raw
  raw="$("$RAD_BIN" resource show Applications.Core/gateways expense-api-gateway -g "$GROUP_NAME" -o json 2>/dev/null | jq -r '.properties.url // .properties.hostname // empty')"
  [ -n "$raw" ] || return 1
  normalize_url "$raw"
}

wait_for_healthz() {
  local url="$1"
  local attempt

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error --max-time 10 "${url%/}/healthz" | jq -e '.status == "ok"' >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  return 1
}

start_port_forward() {
  if [ "$DRY_RUN" = true ]; then
    VALIDATION_BASE_URL="http://127.0.0.1:18080"
    return 0
  fi

  kubectl port-forward -n "$WORKLOAD_NAMESPACE" svc/expense-api 18080:8080 >/dev/null 2>&1 &
  PORT_FORWARD_PID="$!"
  VALIDATION_BASE_URL="http://127.0.0.1:18080"

  wait_for_healthz "$VALIDATION_BASE_URL" || fail "Port-forward to expense-api never became healthy."
}

section "Pre-flight checks"
require_command az
require_command kubectl
require_command jq
require_command docker
require_command curl
require_command dapr
require_command "$RAD_BIN"
actionable_file "$SCRIPT_DIR/publish-radius-recipes.sh"
actionable_file "$SCRIPT_DIR/annotate-service-accounts.sh"
actionable_file "$SCRIPT_DIR/validate-deployment.sh"
actionable_file "$REPO_ROOT/infra/radius/app.bicep"
actionable_file "$REPO_ROOT/infra/radius/environments/azure-radius.bicep"
actionable_file "$REPO_ROOT/infra/radius/environments/azure-radius.parameters.json"
actionable_file "$REPO_ROOT/infra/radius/recipes/azure/state-store.bicep"
rad_version_check

# Auto-populate GHCR credentials from the gh CLI when available.
# These are needed for:
#   1. Publishing recipe Bicep artifacts to GHCR (docker login in publish-radius-recipes.sh)
#   2. Creating ghcr-pull-secret so Kubernetes can pull application container images
# Note: recipe OCI artifacts must be PUBLIC so Radius can pull them without credentials.
#       See require_public_recipe_access() and docs/adr/ghcr-recipe-packages-public.md.
if echo "${RECIPE_REGISTRY}" | grep -q "ghcr.io"; then
  if [ -z "${GHCR_TOKEN:-}" ] || [ -z "${GHCR_USERNAME:-}" ]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      GHCR_USERNAME="${GHCR_USERNAME:-$(gh api user --jq '.login' 2>/dev/null || true)}"
      GHCR_TOKEN="${GHCR_TOKEN:-$(gh auth token 2>/dev/null || true)}"
      if [ -n "${GHCR_USERNAME:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
        log_info "Auto-populated GHCR credentials from 'gh' CLI (user: ${GHCR_USERNAME})."
      fi
    fi
  fi
fi

# Preflight GHCR credentials if targeting ghcr.io and recipes might need publishing.
# This check happens BEFORE any cluster or Azure modifications to fail fast.
if echo "${RECIPE_REGISTRY}" | grep -q "ghcr.io" && [ "$SKIP_RECIPES" = false ]; then
  echo ""
  section "Preflighting GHCR credentials"
  
  # Check if recipes will likely need publishing by testing artifact access
  RECIPES_LIKELY_NEED_PUBLISH=false
  if ! check_recipe_artifact_access state-store >/dev/null 2>&1 || \
     ! check_recipe_artifact_access pubsub >/dev/null 2>&1 || \
     ! check_recipe_artifact_access secrets >/dev/null 2>&1; then
    RECIPES_LIKELY_NEED_PUBLISH=true
    log_info "Recipe artifacts not accessible for tag '${RECIPE_TAG}' — publishing will be required."
  elif ! git -C "$REPO_ROOT" diff --quiet -- infra/radius/recipes/azure 2>/dev/null; then
    RECIPES_LIKELY_NEED_PUBLISH=true
    log_info "Local recipe sources have uncommitted changes — publishing will be required."
  else
    log_info "Recipe artifacts appear accessible for tag '${RECIPE_TAG}' — publishing may be skipped."
  fi
  
  # If publishing is likely needed, verify credentials are set
  if [ "$RECIPES_LIKELY_NEED_PUBLISH" = true ]; then
    if [ -z "${GHCR_TOKEN:-}" ] || [ -z "${GHCR_USERNAME:-}" ]; then
      echo ""
      echo "ERROR: Recipe publishing to ghcr.io is required but GHCR credentials are missing."
      echo ""
      echo "Bootstrap detected that Radius recipe artifacts need to be published to:"
      echo "  ${RECIPE_REGISTRY}"
      echo ""
      echo "However, GHCR_TOKEN and/or GHCR_USERNAME environment variables are not set."
      echo ""
      echo "To fix this, you need to:"
      echo "  1. Create a GitHub Personal Access Token (PAT) with 'write:packages' scope:"
      echo "     → Visit https://github.com/settings/tokens/new"
      echo "     → Select 'write:packages' scope (read:packages is also selected automatically)"
      echo "     → Generate the token and copy it"
      echo ""
      echo "  2. Export the credentials in your shell:"
      echo "     export GHCR_USERNAME=<your-github-username>"
      echo "     export GHCR_TOKEN=<your-personal-access-token>"
      echo ""
      echo "  3. Re-run bootstrap"
      echo ""
      echo "Alternatively, authenticate with the GitHub CLI to auto-populate credentials:"
      echo "  gh auth login"
      echo ""
      fail "Bootstrap cannot continue without GHCR credentials for recipe publishing."
    else
      log_info "GHCR credentials verified: GHCR_USERNAME=${GHCR_USERNAME}"
    fi
  fi
  echo ""
fi

AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null)"
AZURE_SUBSCRIPTION_NAME="$(az account show --query name -o tsv 2>/dev/null)"
AZURE_TENANT_ID_CURRENT="$(az account show --query tenantId -o tsv 2>/dev/null)"
[ -n "$AZURE_SUBSCRIPTION_ID" ] || fail "Azure CLI is not logged in or no subscription is selected."

kubectl cluster-info >/dev/null 2>&1 || fail "kubectl cannot reach the current cluster. Run ./scripts/prepare-cluster.sh first if this cluster still needs preparation."
KUBECTL_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ -n "$KUBECTL_CONTEXT" ] || fail "kubectl has no current context. Run ./scripts/prepare-cluster.sh to set the target cluster context."

dapr status -k >/dev/null 2>&1 || fail "Dapr CLI cannot confirm a Kubernetes control plane. Run ./scripts/prepare-cluster.sh if Dapr is not installed yet."
ensure_control_plane_running "dapr-system" "app.kubernetes.io/part-of=dapr" "Dapr control plane"
ensure_radius_control_plane_running "radius-system"

ensure_radius_workspace_context "$WORKSPACE_NAME" "$GROUP_NAME" "$KUBE_CONTEXT"

if rad_env_exists; then
  EXISTING_ENV=true
  EXISTING_ENV_NAMESPACE="$(fetch_env_namespace)"
else
  EXISTING_ENV=false
  EXISTING_ENV_NAMESPACE=""
fi

if [ "$EXISTING_ENV" = true ]; then
  if ! prompt_confirm "Environment '${ENV_NAME}' already exists. Reuse and update it in place"; then
    fail "Bootstrap aborted because the existing Radius environment was not approved for reuse."
  fi
fi

if [ "$EXISTING_ENV" = true ] && [ -n "$EXISTING_ENV_NAMESPACE" ] && [ "$EXISTING_ENV_NAMESPACE" != "$KUBERNETES_NAMESPACE" ]; then
  if prompt_confirm "Environment '${ENV_NAME}' already uses namespace '${EXISTING_ENV_NAMESPACE}'. Reuse that namespace"; then
    KUBERNETES_NAMESPACE="$EXISTING_ENV_NAMESPACE"
  else
    fail "Bootstrap aborted because the requested namespace does not match the existing Radius environment."
  fi
fi

WORKLOAD_NAMESPACE="${KUBERNETES_NAMESPACE}-${APP_NAME}"
ensure_kubectl_can_write

RESOURCE_GROUP_EXISTS="$(az group exists --name "$RESOURCE_GROUP")"
if [ "$RESOURCE_GROUP_EXISTS" != "true" ]; then
  if prompt_confirm "Resource group '${RESOURCE_GROUP}' does not exist. Create it in '${LOCATION}'"; then
    section "Azure foundation"
    run_cmd az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    RESOURCE_GROUP_CREATED=true
  else
    fail "Bootstrap requires an Azure resource group to continue."
  fi
fi

if radius_azure_credential_registered; then
  AZURE_CREDENTIAL_REGISTERED=true
  # Auto-fill AZURE_CLIENT_ID / AZURE_TENANT_ID from existing credential when not set.
  # This lets operators re-run bootstrap with user-identity az login without
  # exporting every SP env var by hand.
  if [ -n "${AZURE_CLIENT_ID:-}" ]; then
    _AZURE_CLIENT_ID_SOURCE="env"
  fi
  if [ -z "${AZURE_CLIENT_ID:-}" ] || [ -z "${AZURE_TENANT_ID:-}" ]; then
    _rad_cred_json="$("$RAD_BIN" credential show azure -o json 2>/dev/null | sed -n '/^{/,$p' || true)"
    if [ -n "$_rad_cred_json" ]; then
      _cred_client_id="$(printf '%s' "$_rad_cred_json" | jq -r '
        .AzureCredentials.ServicePrincipal.ClientID //
        .AzureCredentials.WorkloadIdentity.ClientID // empty' 2>/dev/null || true)"
      _cred_tenant_id="$(printf '%s' "$_rad_cred_json" | jq -r '
        .AzureCredentials.ServicePrincipal.TenantID //
        .AzureCredentials.WorkloadIdentity.TenantID // empty' 2>/dev/null || true)"
      if [ -z "${AZURE_CLIENT_ID:-}" ] && [ -n "$_cred_client_id" ]; then
        AZURE_CLIENT_ID="$_cred_client_id"
        _AZURE_CLIENT_ID_SOURCE="radius-credential"
        log_info "Auto-detected AZURE_CLIENT_ID from existing Radius credential: ${AZURE_CLIENT_ID}"
      fi
      if [ -z "${AZURE_TENANT_ID:-}" ] && [ -n "$_cred_tenant_id" ]; then
        AZURE_TENANT_ID="$_cred_tenant_id"
        log_info "Auto-detected AZURE_TENANT_ID from existing Radius credential: ${AZURE_TENANT_ID}"
      fi
      unset _rad_cred_json _cred_client_id _cred_tenant_id
    fi
  fi
else
  AZURE_CREDENTIAL_REGISTERED=false
fi

# Early guard: if AZURE_CLIENT_ID is set and AZURE_PRINCIPAL_ID is not, verify the
# service principal actually exists before calling resolve_azure_principal_id.
# Without this, a stale AZURE_CLIENT_ID causes the duplicate "⚠️ Cannot resolve"
# warning block to appear twice (once per resolve_azure_principal_id call below).
if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -z "${AZURE_PRINCIPAL_ID:-}" ]; then
  _sp_guard_saved_client_id="${AZURE_CLIENT_ID}"
  _sp_guard_saved_client_secret="${AZURE_CLIENT_SECRET:-}"
  _sp_guard_saved_tenant_id="${AZURE_TENANT_ID:-}"
  unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID

  _sp_guard_result="$(az ad sp show --id "$_sp_guard_saved_client_id" --query id -o tsv 2>/dev/null || true)"

  export AZURE_CLIENT_ID="$_sp_guard_saved_client_id"
  export AZURE_CLIENT_SECRET="$_sp_guard_saved_client_secret"
  export AZURE_TENANT_ID="$_sp_guard_saved_tenant_id"
  unset _sp_guard_saved_client_id _sp_guard_saved_client_secret _sp_guard_saved_tenant_id

  if [ -z "$_sp_guard_result" ]; then
    unset _sp_guard_result
    if [ "$CREATE_SPN" = true ]; then
      # --create-spn was passed — warn about the stale creds and clear them so
      # the SP creation block below starts with a clean slate.
      if [ "${_AZURE_CLIENT_ID_SOURCE:-}" = "radius-credential" ]; then
        log_warning "Radius credential references a stale SP '${AZURE_CLIENT_ID}'. It will be replaced by a new service principal."
      else
        log_warning "Service principal '${AZURE_CLIENT_ID}' does not exist. Ignoring stale credentials and creating a new service principal..."
      fi
      unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID
      _AZURE_CLIENT_ID_SOURCE=""
      AZURE_CREDENTIAL_REGISTERED=false
    elif [ "${_AZURE_CLIENT_ID_SOURCE:-}" = "radius-credential" ]; then
      log_error "The Radius credential stored for this workspace references a stale or deleted service principal."
      log_info  "  SP ID '${AZURE_CLIENT_ID}' no longer exists in the current Azure AD tenant."
      log_info  "  To fix this:"
      log_info  "    1. Clear the stale credential:"
      log_info  "         rad credential unregister azure"
      log_info  "    2. Re-run bootstrap with --create-spn to register a fresh service principal:"
      log_info  "         ./scripts/bootstrap.sh --create-spn [other flags]"
      unset _AZURE_CLIENT_ID_SOURCE
      fail "Cannot resolve the Microsoft Entra principal — service principal does not exist."
    else
      log_error "Service principal '${AZURE_CLIENT_ID}' does not exist in the current Azure AD tenant."
      log_info  "This AZURE_CLIENT_ID is stale or from a different tenant. Unset it and re-run."
      log_info  "To fix this:"
      log_info  "  1. Unset AZURE_CLIENT_ID (and AZURE_CLIENT_SECRET / AZURE_TENANT_ID) and re-run."
      log_info  "  2. Or export credentials for a service principal that exists in the current tenant:"
      log_info  "       az ad sp list --show-mine --query '[].appId' -o tsv"
      unset _AZURE_CLIENT_ID_SOURCE
      fail "Cannot resolve the Microsoft Entra principal — service principal does not exist."
    fi
  else
    # SP exists — cache the resolved object ID so resolve_azure_principal_id()
    # short-circuits without a redundant az ad sp show call.
    AZURE_PRINCIPAL_ID="$_sp_guard_result"
    log_info "Cached principal object ID from early guard: ${AZURE_PRINCIPAL_ID}"
  fi
  unset _sp_guard_result _AZURE_CLIENT_ID_SOURCE
fi

# SP creation block — runs when --create-spn is passed and no valid AZURE_CLIENT_ID
# is set (either cleared by the stale guard above, or never set in the first place).
if [ -z "${AZURE_CLIENT_ID:-}" ] && [ "$CREATE_SPN" = true ]; then
  section "Creating Azure service principal"
  log_info "Creating Azure service principal for Radius"
  log_info "Radius requires a service principal to provision Azure-backed recipe resources."

  SPN_NAME="radiusclaim-radius-sp"
  EXISTING_APP_ID="$(az ad sp list --display-name "$SPN_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)"

  if [ -n "$EXISTING_APP_ID" ]; then
    log_warning "Service principal '${SPN_NAME}' already exists (App ID: ${EXISTING_APP_ID})"
    log_info "You can reuse it by exporting AZURE_CLIENT_ID and AZURE_CLIENT_SECRET,"
    log_info "or create a new one with a timestamp suffix."

    if ! prompt_confirm "Create a new service principal with timestamp suffix instead?"; then
      log_info "Ensuring existing service principal has Contributor role..."

      _reuse_saved_client_id="${AZURE_CLIENT_ID:-}"
      _reuse_saved_client_secret="${AZURE_CLIENT_SECRET:-}"
      _reuse_saved_tenant_id="${AZURE_TENANT_ID:-}"
      unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID

      SUBSCRIPTION_SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}"
      if az role assignment create \
        --assignee "$EXISTING_APP_ID" \
        --role Contributor \
        --scope "$SUBSCRIPTION_SCOPE" \
        --output none 2>/dev/null; then
        log_success "Role assignment: Contributor on subscription ${AZURE_SUBSCRIPTION_ID}"
      else
        if az role assignment list \
          --assignee "$EXISTING_APP_ID" \
          --role Contributor \
          --scope "$SUBSCRIPTION_SCOPE" \
          --query "[0].id" -o tsv >/dev/null 2>&1; then
          log_success "Role assignment: Contributor already exists on subscription ${AZURE_SUBSCRIPTION_ID}"
        else
          export AZURE_CLIENT_ID="$_reuse_saved_client_id"
          export AZURE_CLIENT_SECRET="$_reuse_saved_client_secret"
          export AZURE_TENANT_ID="$_reuse_saved_tenant_id"
          fail "Failed to verify or assign Contributor role to service principal. Check Azure permissions."
        fi
      fi

      export AZURE_CLIENT_ID="$_reuse_saved_client_id"
      export AZURE_CLIENT_SECRET="$_reuse_saved_client_secret"
      export AZURE_TENANT_ID="$_reuse_saved_tenant_id"
      unset _reuse_saved_client_id _reuse_saved_client_secret _reuse_saved_tenant_id

      log_error "Cannot proceed without service principal credentials."
      echo ""
      echo "To reuse the existing service principal, export these environment variables:"
      echo "  export AZURE_CLIENT_ID='${EXISTING_APP_ID}'"
      echo "  export AZURE_CLIENT_SECRET='<your-secret>'"
      echo "  export AZURE_TENANT_ID='$(az account show --query tenantId -o tsv)'"
      echo ""
      echo "Then re-run this script."
      exit 1
    fi

    SPN_NAME="${SPN_NAME}-$(date +%Y%m%d-%H%M%S)"
  else
    if ! prompt_confirm "Create service principal '${SPN_NAME}' now?"; then
      log_error "Service principal creation declined."
      echo ""
      echo "To create a service principal manually, run:"
      echo "  az ad sp create-for-rbac --name '${SPN_NAME}' --role Contributor --scopes /subscriptions/${AZURE_SUBSCRIPTION_ID}"
      echo ""
      echo "Then export these environment variables and re-run this script:"
      echo "  export AZURE_CLIENT_ID='<appId>'"
      echo "  export AZURE_CLIENT_SECRET='<password>'"
      echo "  export AZURE_TENANT_ID='<tenant>'"
      exit 1
    fi
  fi

  log_info "Creating service principal '${SPN_NAME}'..."
  SPN_JSON="$(az ad sp create-for-rbac \
    --name "$SPN_NAME" \
    --role Contributor \
    --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
    --output json)" || fail "Failed to create service principal."

  log_success "Role assignment: Contributor on subscription ${AZURE_SUBSCRIPTION_ID}"

  export AZURE_CLIENT_ID="$(printf '%s' "$SPN_JSON" | jq -r '.appId')"
  export AZURE_CLIENT_SECRET="$(printf '%s' "$SPN_JSON" | jq -r '.password')"
  export AZURE_TENANT_ID="$(printf '%s' "$SPN_JSON" | jq -r '.tenant')"

  [ -n "$AZURE_CLIENT_ID" ] || fail "Failed to parse AZURE_CLIENT_ID from service principal response."
  [ -n "$AZURE_CLIENT_SECRET" ] || fail "Failed to parse AZURE_CLIENT_SECRET from service principal response."
  [ -n "$AZURE_TENANT_ID" ] || fail "Failed to parse AZURE_TENANT_ID from service principal response."

  # Cache the principal object ID immediately — avoids Azure AD propagation
  # delay when resolve_azure_principal_id() queries it seconds later.
  _new_sp_principal_id="$(az ad sp show --id "${AZURE_CLIENT_ID}" --query id -o tsv 2>/dev/null || true)"
  if [ -n "$_new_sp_principal_id" ]; then
    AZURE_PRINCIPAL_ID="$_new_sp_principal_id"
    log_info "Cached principal object ID from new SP: ${AZURE_PRINCIPAL_ID}"
  fi

  echo ""
  log_warning "⚠️  SAVE THESE CREDENTIALS NOW — the client secret cannot be retrieved again."
  echo ""
  echo "Service principal created:"
  echo "  Name            : ${SPN_NAME}"
  echo "  AZURE_CLIENT_ID : ${AZURE_CLIENT_ID}"
  echo "  AZURE_CLIENT_SECRET : ${AZURE_CLIENT_SECRET}"
  echo "  AZURE_TENANT_ID : ${AZURE_TENANT_ID}"
  echo ""
  echo "Add them to your shell profile or a .env file (excluded from git):"
  echo "  export AZURE_CLIENT_ID='${AZURE_CLIENT_ID}'"
  echo "  export AZURE_CLIENT_SECRET='${AZURE_CLIENT_SECRET}'"
  echo "  export AZURE_TENANT_ID='${AZURE_TENANT_ID}'"
  echo ""

  log_success "Service principal configured for this session"
  SHOULD_REGISTER_AZURE_CREDENTIAL=true
  AZURE_CREDENTIAL_REGISTERED=false
elif [ -z "${AZURE_CLIENT_ID:-}" ] && [ "$CREATE_SPN" = false ]; then
  # No AZURE_CLIENT_ID and no --create-spn — can't continue
  fail "Azure service principal credentials are not set.
Pass --create-spn to create one automatically, or export:
  AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID"
fi

# Consolidate auth context resolution (subscription, tenant, principal ID)
# This is the single source of truth — validates subscription/tenant match
# and resolves the principal ID for all downstream RBAC operations.
# Called once at the start of auth setup; result cached in AZURE_PRINCIPAL_ID_CACHED.
AZURE_PRINCIPAL_ID_CACHED="$(resolve_auth_context)"

# Use cached principal ID for RBAC
if [ -n "$AZURE_PRINCIPAL_ID_CACHED" ]; then
  ensure_radius_recipe_rbac "$AZURE_SUBSCRIPTION_ID" "$RESOURCE_GROUP" "$AZURE_PRINCIPAL_ID_CACHED"
fi

if [ "$AZURE_CREDENTIAL_REGISTERED" = false ]; then
  if prompt_confirm "Radius Azure credential is not registered. Register it now"; then
    SHOULD_REGISTER_AZURE_CREDENTIAL=true
  else
    fail "Radius cannot provision Azure-backed recipes without an Azure credential."
  fi
elif [ -n "${AZURE_CLIENT_SECRET:-}" ]; then
  # Credential exists but a client secret is available — re-register to keep the
  # stored secret fresh (covers rotated-secret scenarios).
  SHOULD_REGISTER_AZURE_CREDENTIAL=true
fi

RECIPES_NEED_PUBLISH_REASON=""
if "$SKIP_RECIPES"; then
  log_warning "Recipe publishing is skipped by flag. Bootstrap will trust existing OCI artifacts."
else
  if ! check_recipe_artifact_access state-store || ! check_recipe_artifact_access pubsub || ! check_recipe_artifact_access secrets; then
    RECIPES_NEED_PUBLISH_REASON="OCI recipe artifacts for tag '${RECIPE_TAG}' are not accessible"
  elif ! git -C "$REPO_ROOT" diff --quiet -- infra/radius/recipes/azure; then
    RECIPES_NEED_PUBLISH_REASON="local recipe sources have uncommitted changes"
  fi

  if [ -n "$RECIPES_NEED_PUBLISH_REASON" ]; then
    if prompt_confirm "${RECIPES_NEED_PUBLISH_REASON}. Publish recipes to '${RECIPE_REGISTRY}' now"; then
      SHOULD_PUBLISH_RECIPES=true
    else
      fail "Bootstrap cannot continue with potentially stale recipe artifacts. Use --skip-recipes only when the registry tag is already correct."
    fi
  fi
fi

if rad_app_exists; then
  if prompt_confirm "Application '${APP_NAME}' already exists. Redeploy it in place"; then
    SKIP_APP_DEPLOY=false
  else
    SKIP_APP_DEPLOY=true
  fi
fi

if kubectl get namespace "$WORKLOAD_NAMESPACE" >/dev/null 2>&1 && kubectl get components -n "$WORKLOAD_NAMESPACE" >/dev/null 2>&1; then
  if kubectl get components -n "$WORKLOAD_NAMESPACE" -o json | jq -e '.items | length > 0' >/dev/null 2>&1; then
    if prompt_confirm "Dapr components already exist in '${WORKLOAD_NAMESPACE}'. Refresh them from live Radius outputs"; then
      SKIP_COMPONENT_REFRESH=false
    else
      SKIP_COMPONENT_REFRESH=true
    fi
  fi
fi

# ==> Auth Setup Flow
# 1. Validate mutual exclusion of auth mode flags
# 2. Resolve auth mode (sp, wi, or auto-detect)
# 3. Validate subscription and tenant match before SP creation
# 4. Optionally create or validate service principal
# 5. Optionally set up workload identity (OIDC + addons)
# 6. Validate Dapr control-plane auth
# 7. Register Radius credential
#
# Mutual exclusion: --azure-auth-mode sp and --setup-workload-identity are mutually exclusive
# If both are set, bootstrap will fail with an explicit error (see below).

# Validate auth mode flags: cannot use both --azure-auth-mode sp AND --setup-workload-identity
if [ "$AZURE_AUTH_MODE" = "sp" ] && [ "$SETUP_WORKLOAD_IDENTITY" = "true" ]; then
  fail "Cannot use both --azure-auth-mode sp AND --setup-workload-identity together.
Choose ONE:
  (1) --azure-auth-mode sp        — Service Principal with client secret (no cluster changes needed)
  (2) --setup-workload-identity   — Workload Identity with federated credentials (enables OIDC + addons)

These modes are mutually exclusive because:
  • SP mode uses AZURE_CLIENT_SECRET stored in the cluster
  • WI mode uses OIDC federation with no secrets in the cluster

See docs/phase-7-demo-walkthrough.md#auth-modes for details."
fi

AZURE_AUTH_MODE_RESOLVED="$(resolve_azure_auth_mode)"

section "Azure Authentication"
if [ -n "$AZURE_AUTH_MODE_RESOLVED" ]; then
  log_auth_mode_explanation "$AZURE_AUTH_MODE_RESOLVED"
elif [ "$SHOULD_REGISTER_AZURE_CREDENTIAL" = false ]; then
  log_auth_mode_explanation "reuse-existing"
fi

# Auto-enable workload identity setup if auth mode resolves to 'wi' and addons
# are not already enabled. This ensures Dapr component backfill and credential
# registration work without requiring an explicit --setup-workload-identity flag.
# Must run before credential registration so the cluster is ready for wi mode.
if [ "$SETUP_WORKLOAD_IDENTITY" = false ] && [ "$AZURE_AUTH_MODE_RESOLVED" = "wi" ]; then
  # Check if addons are already enabled on the cluster; skip setup if they are.
  if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" -o json 2>/dev/null | jq -e '.oidcIssuerProfile and .oidcIssuerProfile.enabled == true and .workloadIdentityProfile and .workloadIdentityProfile.enabled == true' &>/dev/null; then
    SETUP_WORKLOAD_IDENTITY=true
    log_info "Detected workload identity auth mode; will auto-enable OIDC issuer and workload identity addons on AKS."
  fi
fi

# Enable OIDC issuer + workload identity on AKS if requested or auto-detected.
# This must run before credential registration so the cluster is ready for wi mode.
if [ "$SETUP_WORKLOAD_IDENTITY" = true ]; then
  section "Enabling OIDC issuer and workload identity on AKS cluster"
  # Auto-discover the cluster name if the configured default doesn't exist.
  if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" &>/dev/null; then
    discovered="$(az aks list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null || true)"
    if [ -n "$discovered" ]; then
      log_info "AKS cluster '${AKS_CLUSTER_NAME}' not found; using discovered cluster '${discovered}'."
      AKS_CLUSTER_NAME="$discovered"
    else
      fail "No AKS cluster found in resource group '${RESOURCE_GROUP}'. Pass --cluster-name <name> explicitly."
    fi
  fi
  run_cmd az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --enable-oidc-issuer \
    --enable-workload-identity
  # Force wi mode only when auto mode hasn't already resolved to sp (via client secret).
  # --setup-workload-identity configures the cluster for workload pod auth; Radius itself
  # should continue using SP credentials when AZURE_CLIENT_SECRET is available.
  if [ "$AZURE_AUTH_MODE" = "auto" ] && [ "$AZURE_AUTH_MODE_RESOLVED" != "sp" ]; then
    AZURE_AUTH_MODE="wi"
    AZURE_AUTH_MODE_RESOLVED="wi"
  fi

  # Deploy workload identity infrastructure (managed identity + federated credentials)
  section "Deploying workload identity infrastructure"
  
  # Retrieve OIDC issuer URL from cluster
  OIDC_ISSUER_URL=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query "oidcIssuerProfile.issuerUrl" \
    -o tsv 2>/dev/null || true)
  
  if [ -z "$OIDC_ISSUER_URL" ]; then
    fail "Could not retrieve OIDC issuer URL from AKS cluster. Ensure workload identity addon is enabled."
  fi
  
  log_info "OIDC issuer URL: $OIDC_ISSUER_URL"
  
  # Deploy Bicep template for workload identity
  LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
  WORKLOAD_IDENTITY_DEPLOYMENT="workload-identity-$(date +%s)"
  
  run_cmd az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WORKLOAD_IDENTITY_DEPLOYMENT" \
    --template-file "$REPO_ROOT/infra/azure/workload-identity.bicep" \
    --parameters location="$LOCATION" \
    --parameters aksOidcIssuer="$OIDC_ISSUER_URL" \
    --parameters kubernetesNamespace="$WORKLOAD_NAMESPACE"
  
  # Capture outputs from deployment
  MANAGED_IDENTITY_CLIENT_ID=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WORKLOAD_IDENTITY_DEPLOYMENT" \
    --query "properties.outputs.managedIdentityClientId.value" \
    -o tsv)
  
  MANAGED_IDENTITY_PRINCIPAL_ID=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WORKLOAD_IDENTITY_DEPLOYMENT" \
    --query "properties.outputs.managedIdentityPrincipalId.value" \
    -o tsv)
  
  # Capture identity name from deployment output — used as daprAzurePrincipalName
  # in the environment Bicep (PostgreSQL Entra admin display name / connection user).
  MANAGED_IDENTITY_NAME=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WORKLOAD_IDENTITY_DEPLOYMENT" \
    --query "properties.outputs.managedIdentityName.value" \
    -o tsv)
  
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ] || [ -z "$MANAGED_IDENTITY_PRINCIPAL_ID" ] || [ -z "$MANAGED_IDENTITY_NAME" ]; then
    fail "Failed to retrieve managed identity outputs from Bicep deployment. Expected: managedIdentityClientId, managedIdentityPrincipalId, managedIdentityName."
  fi
  
  log_success "Workload identity deployed"
  log_info "  Name:         $MANAGED_IDENTITY_NAME"
  log_info "  Client ID:    $MANAGED_IDENTITY_CLIENT_ID"
  log_info "  Principal ID: $MANAGED_IDENTITY_PRINCIPAL_ID"
  
  # Override AZURE_CLIENT_ID and AZURE_PRINCIPAL_ID with values from Bicep
  export AZURE_CLIENT_ID_CACHED="$MANAGED_IDENTITY_CLIENT_ID"
  export AZURE_PRINCIPAL_ID_CACHED="$MANAGED_IDENTITY_PRINCIPAL_ID"
else
  # Workload identity setup was skipped (already enabled on cluster).
  # Still need to capture the managed identity principal ID for the environment Bicep.
  # The managed identity was created in a prior bootstrap run; look it up by name.
  section "Retrieving existing workload identity"
  MANAGED_IDENTITY_NAME="radiusclaim-workload-identity"
  
  MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MANAGED_IDENTITY_NAME" \
    --query "clientId" \
    -o tsv 2>/dev/null || true)
  
  MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MANAGED_IDENTITY_NAME" \
    --query "principalId" \
    -o tsv 2>/dev/null || true)
  
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ] || [ -z "$MANAGED_IDENTITY_PRINCIPAL_ID" ]; then
    fail "Could not retrieve existing workload identity '$MANAGED_IDENTITY_NAME'. The managed identity may not exist in resource group '$RESOURCE_GROUP', or it may have a different name. Run bootstrap with --setup-workload-identity to create it."
  fi
  
  export AZURE_CLIENT_ID_CACHED="$MANAGED_IDENTITY_CLIENT_ID"
  export AZURE_PRINCIPAL_ID_CACHED="$MANAGED_IDENTITY_PRINCIPAL_ID"
  log_success "Workload identity retrieved"
  log_info "  Client ID:    $MANAGED_IDENTITY_CLIENT_ID"
  log_info "  Principal ID: $MANAGED_IDENTITY_PRINCIPAL_ID"
fi
test -n "${AZURE_CLIENT_ID:-}" || fail "AZURE_CLIENT_ID is required for the Microsoft Entra statestore path."
test -n "${AZURE_TENANT_ID:-}" || fail "AZURE_TENANT_ID is required for the Microsoft Entra statestore path."
# Validate that principal ID is available from workload identity
test -n "$AZURE_PRINCIPAL_ID_CACHED" || fail "Could not resolve the workload identity principal object ID. The recipes need this to create RBAC assignments. Run bootstrap with --setup-workload-identity to create the identity, or check that the managed identity exists in Azure."
if [ "$SHOULD_REGISTER_AZURE_CREDENTIAL" = true ] && [ -z "$AZURE_AUTH_MODE_RESOLVED" ]; then
  fail "Azure credential registration was approved, but the required Azure auth environment variables are not set."
fi

section "Bootstrap plan"
echo "Azure subscription : ${AZURE_SUBSCRIPTION_NAME} (${AZURE_SUBSCRIPTION_ID})"
echo "Azure tenant       : ${AZURE_TENANT_ID_CURRENT}"
echo "kubectl context    : ${KUBECTL_CONTEXT}"
echo "Radius workspace   : ${WORKSPACE_NAME}"
echo "Radius group       : ${GROUP_NAME}"
echo "Environment        : ${ENV_NAME}"
echo "Env namespace      : ${KUBERNETES_NAMESPACE}"
echo "Workload namespace : ${WORKLOAD_NAMESPACE}"
echo "Resource group     : ${RESOURCE_GROUP}"
echo "Container registry : ${CONTAINER_REGISTRY}"
echo "Recipe registry    : ${RECIPE_REGISTRY}"
echo "Image tag          : ${IMAGE_TAG}"
echo "Recipe tag         : ${RECIPE_TAG}"
echo "Azure auth mode    : ${AZURE_AUTH_MODE_RESOLVED:-reuse-existing}"
if [ "$AZURE_AUTH_MODE_RESOLVED" = "sp" ]; then
  echo "                     (detected: client ID + client SECRET + tenant ID)"
elif [ "$AZURE_AUTH_MODE_RESOLVED" = "wi" ]; then
  echo "                     (detected: client ID + tenant ID, no secret)"
elif [ "$AZURE_AUTH_MODE_RESOLVED" = "" ] && [ "$SHOULD_REGISTER_AZURE_CREDENTIAL" = false ]; then
  echo "                     (reusing existing Radius credential)"
fi
echo "Dapr Azure client  : ${AZURE_CLIENT_ID}"
echo "Publish recipes    : ${SHOULD_PUBLISH_RECIPES}"
echo "Push images        : ${SKIP_IMAGE_PUSH} (false means push)"
echo "Redeploy app       : $([ "$SKIP_APP_DEPLOY" = true ] && echo false || echo true)"
echo "Refresh components : $([ "$SKIP_COMPONENT_REFRESH" = true ] && echo false || echo true)"
echo "Run validation     : $([ "$SKIP_VALIDATION" = true ] && echo false || echo true)"

section "Radius environment setup"
if [ "$DRY_RUN" = true ]; then
  run_cmd "$RAD_BIN" env create "$ENV_NAME"
else
  "$RAD_BIN" env create "$ENV_NAME" >/dev/null 2>&1 || true
fi
run_cmd "$RAD_BIN" env switch "$ENV_NAME"

if [ "$SHOULD_REGISTER_AZURE_CREDENTIAL" = true ]; then
  section "Registering Azure credential with Radius"
  case "$AZURE_AUTH_MODE_RESOLVED" in
    sp)
      run_cmd "$RAD_BIN" credential register azure sp \
        --client-id "${AZURE_CLIENT_ID}" \
        --client-secret "${AZURE_CLIENT_SECRET}" \
        --tenant-id "${AZURE_TENANT_ID}"
      ;;
    wi)
      run_cmd "$RAD_BIN" credential register azure wi \
        --client-id "${AZURE_CLIENT_ID}" \
        --tenant-id "${AZURE_TENANT_ID}"
      ;;
    *)
      fail "Unsupported resolved Azure auth mode '${AZURE_AUTH_MODE_RESOLVED}'."
      ;;
  esac
fi

section "Resolving Radius resource naming"
initialize_radius_resource_naming

ensure_azure_secret_store_ready

if [ "$SHOULD_PUBLISH_RECIPES" = true ]; then
  section "Publishing Radius recipes"
  run_cmd env RAD_BIN="$RAD_BIN" "$SCRIPT_DIR/publish-radius-recipes.sh" "$RECIPE_REGISTRY" "$RECIPE_TAG"
fi

section "Verifying recipe OCI artifacts are publicly accessible"
require_public_recipe_access

section "Deploying Radius environment"

# Check if the Radius environment has been deployed before.
# On first-run, the environment doesn't exist yet so we skip rad env update until after bicep deploy.
# On re-run, the environment exists so we must update it BEFORE bicep deploy.
ENV_EXISTS=false
if "$RAD_BIN" env show "${ENV_NAME}" &>/dev/null; then
  ENV_EXISTS=true
fi

if [ "$ENV_EXISTS" = true ]; then
  # Environment already exists — register Azure provider scope BEFORE bicep deploy.
  # This tells Radius WHERE to deploy Azure resources (required for bicep processing).
  section "Registering Azure provider scope with Radius (pre-deploy)"
  run_cmd "$RAD_BIN" env update "${ENV_NAME}" \
    --azure-subscription-id "${AZURE_SUBSCRIPTION_ID}" \
    --azure-resource-group "${RESOURCE_GROUP}"
fi

# Guard against a namespace collision: if a stale Radius environment from a
# prior run uses the same Kubernetes namespace (${KUBERNETES_NAMESPACE}) under a
# different name (e.g. 'radiusclaim-azure' vs the canonical '${ENV_NAME}'),
# Radius returns HTTP 409 Conflict on the deploy.  Detect and remove it first.
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

section "Validating Dapr workload identity principal ID"
test -n "${AZURE_PRINCIPAL_ID_CACHED:-}" || fail "Dapr workload identity principal ID is not set. This is required by the environment Bicep recipes to create RBAC role assignments on Azure resources. The recipes cannot function without this value."
log_success "Principal ID validated: ${AZURE_PRINCIPAL_ID_CACHED}"

section "Resolving Azure subscription ID for CLI parameter injection"
RESOLVED_SUBSCRIPTION_ID="$(az account show -o tsv --query id 2>/dev/null)" || RESOLVED_SUBSCRIPTION_ID=""
if [ -z "$RESOLVED_SUBSCRIPTION_ID" ]; then
  fail "Failed to resolve subscription ID. Ensure 'az account show' succeeds and returns a valid subscription ID."
fi
log_success "Subscription ID resolved: ${RESOLVED_SUBSCRIPTION_ID}"

# Determine the best location for PostgreSQL Flexible Server.
# The resource group location (LOCATION) may not have PostgreSQL quota; in that
# case, fall back to the AKS cluster's region which is known to have capacity.
# Allow explicit override via POSTGRES_LOCATION env var (e.g. when the main region
# is quota-restricted for PostgreSQL but has AKS capacity).
POSTGRES_LOCATION="${POSTGRES_LOCATION:-${LOCATION}}"
if [ "${POSTGRES_LOCATION}" != "${LOCATION}" ]; then
  log_info "Using explicit POSTGRES_LOCATION override '${POSTGRES_LOCATION}' for PostgreSQL Flexible Server."
fi
# POSTGRES_NAME_SUFFIX defaults to RANDOM_NAME_SUFFIX; may be overridden if the default
# name is ARM-registered at a different location (ARM caches location for failed PUTs).
POSTGRES_NAME_SUFFIX="${RANDOM_NAME_SUFFIX}"
# Only auto-detect location when no explicit POSTGRES_LOCATION override was set.
if [ "${POSTGRES_LOCATION}" = "${LOCATION}" ] && \
   ! az postgres flexible-server list-skus --location "${LOCATION}" --query "[0].name" -o tsv &>/dev/null; then
  log_warn "PostgreSQL Flexible Server is not available in location '${LOCATION}'."
  AKS_CLUSTER_LOCATION="$(az aks show --resource-group "${RESOURCE_GROUP}" --name "${AKS_CLUSTER_NAME}" --query location -o tsv 2>/dev/null || true)"
  if [ -n "${AKS_CLUSTER_LOCATION}" ] && az postgres flexible-server list-skus --location "${AKS_CLUSTER_LOCATION}" --query "[0].name" -o tsv &>/dev/null; then
    POSTGRES_LOCATION="${AKS_CLUSTER_LOCATION}"
    log_info "Using AKS cluster location '${POSTGRES_LOCATION}' for PostgreSQL Flexible Server."
    # If the name suffix was already attempted at the old location, ARM records the ghost.
    # Check whether that name already exists at the new location; if not and it was tried at
    # the old location, generate a fresh suffix to avoid InvalidResourceLocation from ARM.
    if az postgres flexible-server show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "pgstate${RANDOM_NAME_SUFFIX}" &>/dev/null; then
      log_info "PostgreSQL server 'pgstate${RANDOM_NAME_SUFFIX}' exists; will reuse."
    else
      # Try to detect ghost: attempt REST GET at old location. If ARM returns a location
      # conflict on a test PUT we'll catch it; simplest heuristic is unconditional override.
      EXISTING_LOCATION="$(az rest --method GET \
        --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforPostgreSQL/flexibleServers/pgstate${RANDOM_NAME_SUFFIX}?api-version=2023-06-01-preview" \
        --query "location" -o tsv 2>/dev/null || true)"
      if [ -n "${EXISTING_LOCATION}" ] && [ "${EXISTING_LOCATION}" != "${POSTGRES_LOCATION}" ]; then
        POSTGRES_NAME_SUFFIX="$(openssl rand -hex 3)"
        log_warn "Existing name 'pgstate${RANDOM_NAME_SUFFIX}' is ARM-registered in '${EXISTING_LOCATION}' (not '${POSTGRES_LOCATION}'). Using new suffix '${POSTGRES_NAME_SUFFIX}'."
      fi
    fi
  else
    log_warn "Could not auto-detect PostgreSQL-capable location. Using '${LOCATION}' and relying on ARM to handle it."
  fi
fi

ENV_DEPLOY_ARGS=(
  deploy
  "$REPO_ROOT/infra/radius/environments/azure-radius.bicep"
  --parameters "@${REPO_ROOT}/infra/radius/environments/azure-radius.parameters.json"
  --parameters "environmentName=${ENV_NAME}"
  --parameters "kubernetesNamespace=${KUBERNETES_NAMESPACE}"
  --parameters "applicationName=${APP_NAME}"
  --parameters "azureProviderScope=/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
  --parameters "azureSubscriptionId=${AZURE_SUBSCRIPTION_ID}"
  --parameters "azureResourceGroupName=${RESOURCE_GROUP}"
  --parameters "location=${LOCATION}"
  --parameters "postgresLocation=${POSTGRES_LOCATION}"
  --parameters "postgresNameSuffix=${POSTGRES_NAME_SUFFIX}"
  --parameters "daprAzurePrincipalId=${AZURE_PRINCIPAL_ID_CACHED}"
  --parameters "daprAzureClientId=${AZURE_CLIENT_ID_CACHED}"
  --parameters "daprAzurePrincipalName=${MANAGED_IDENTITY_NAME}"
  --parameters "azureTenantId=${AZURE_TENANT_ID}"
  --parameters "recipeRegistry=${RECIPE_REGISTRY}"
  --parameters "recipeTag=${RECIPE_TAG}"
  --parameters "randomNameSuffix=${RANDOM_NAME_SUFFIX}"
)
run_cmd "$RAD_BIN" "${ENV_DEPLOY_ARGS[@]}"

if [ "$ENV_EXISTS" = false ]; then
  # First-run: environment created by bicep deploy — register Azure provider scope AFTER.
  section "Registering Azure provider scope with Radius (post-deploy)"
  run_cmd "$RAD_BIN" env update "${ENV_NAME}" \
    --azure-subscription-id "${AZURE_SUBSCRIPTION_ID}" \
    --azure-resource-group "${RESOURCE_GROUP}"
fi

if [ "$DRY_RUN" != true ]; then
  DEPLOYED_ENV_NAMESPACE="$(fetch_env_namespace)"
  if [ -n "$DEPLOYED_ENV_NAMESPACE" ]; then
    KUBERNETES_NAMESPACE="$DEPLOYED_ENV_NAMESPACE"
    WORKLOAD_NAMESPACE="${KUBERNETES_NAMESPACE}-${APP_NAME}"
  fi
fi

if [ "$SKIP_APP_DEPLOY" = false ] && [ "$SKIP_IMAGE_PUSH" = false ]; then
  section "Building and pushing service images"
  build_and_push_service expense-api "$REPO_ROOT/src/expense-api/Dockerfile"
  build_and_push_service workflow-engine "$REPO_ROOT/src/workflow-engine/Dockerfile"
  build_and_push_service notification-svc "$REPO_ROOT/src/notification-svc/Dockerfile"
fi

if [ "$SKIP_APP_DEPLOY" = false ]; then
  # Pre-create the workload namespace and GHCR pull secret BEFORE rad deploy so
  # that Kubernetes can pull private images as soon as Radius creates the pods.
  section "Ensuring GHCR image pull secret (pre-deploy)"
  if [ "$DRY_RUN" != true ]; then
    kubectl create namespace "$WORKLOAD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
  fi
  
  if needs_ghcr_pull_secret; then
    if kubectl get secret ghcr-pull-secret -n "$WORKLOAD_NAMESPACE" >/dev/null 2>&1; then
      echo "  ✓ ghcr-pull-secret already exists in $WORKLOAD_NAMESPACE"
    elif [ -n "${GHCR_TOKEN:-}" ] && [ -n "${GHCR_USERNAME:-}" ]; then
      run_cmd kubectl create secret docker-registry ghcr-pull-secret \
        --docker-server=ghcr.io \
        --docker-username="${GHCR_USERNAME}" \
        --docker-password="${GHCR_TOKEN}" \
        -n "$WORKLOAD_NAMESPACE"
      echo "  ✓ ghcr-pull-secret created in $WORKLOAD_NAMESPACE"
    else
      log_warning "GHCR_USERNAME/GHCR_TOKEN not set — private GHCR images may fail to pull."
      log_warning "Set GHCR_USERNAME and GHCR_TOKEN before running bootstrap, or create the secret manually:"
      echo "    kubectl create secret docker-registry ghcr-pull-secret --docker-server=ghcr.io --docker-username=<user> --docker-password=<PAT> -n $WORKLOAD_NAMESPACE"
    fi
  else
    echo "  ℹ Skipping pull secret — using public GHCR or managed identity auth."
  fi

  section "Checking for stuck Radius resources (pre-deploy)"
  cleanup_stuck_radius_resources "$APP_NAME" "$GROUP_NAME" "$WORKSPACE_NAME"

  # Guard against a stale application resource bound to a different environment.
  # Radius returns BadRequest if '${APP_NAME}' already exists in the control plane
  # under a different environment (e.g. 'radiusclaim-azure' vs the canonical '${ENV_NAME}').
  # This mirrors the namespace-collision guard for environments above.
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
        "$RAD_BIN" resource delete Applications.Core/applications "${_stale_app}" \
          -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
        log_info "Stale application '${_stale_app}' removed."
      fi
    fi
    unset _stale_app _target_env_id _app_json

    # Guard against namespace mismatch: Radius requires the application to be
    # deleted and redeployed when changing its Kubernetes namespace.
    _existing_app_ns="$("$RAD_BIN" app show "${APP_NAME}" -o json 2>/dev/null \
      | sed -n '/^{/,$p' \
      | jq -r '.properties.status.compute.namespace // empty' 2>/dev/null || true)"
    if [ -n "$_existing_app_ns" ] && [ "$_existing_app_ns" != "$WORKLOAD_NAMESPACE" ]; then
      log_warning "Application '${APP_NAME}' namespace '${_existing_app_ns}' differs from target '${WORKLOAD_NAMESPACE}' — deleting for namespace migration."
      "$RAD_BIN" app delete "${APP_NAME}" \
        -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      "$RAD_BIN" resource delete Applications.Core/applications "${APP_NAME}" \
        -g "$GROUP_NAME" -w "$WORKSPACE_NAME" --yes 2>/dev/null || true
      log_info "Application '${APP_NAME}' removed for namespace migration to '${WORKLOAD_NAMESPACE}'."
    fi
    unset _existing_app_ns
  fi

  # Guard against stale Dapr component resources bound to a different environment.
  # Dapr secretStores, stateStores, and pubSubBrokers can also become stale with
  # environment mismatches, causing BadRequest during deployment just like application
  # resources. Detect and delete them before deploying.
  if [ "$DRY_RUN" != true ]; then
    _target_env_id="/planes/radius/local/resourcegroups/${GROUP_NAME}/providers/Applications.Core/environments/${ENV_NAME}"
    
    # Check and clean stale secretStores
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
          log_warning "Dapr secretStore '${_secret_name}' is bound to a different environment — removing to allow idempotent redeploy."
          delete_dapr_resource_with_verify \
            Applications.Dapr/secretStores "${_secret_name}" "$GROUP_NAME" "$WORKSPACE_NAME"
        done <<< "$_stale_secrets"
      fi
    fi
    
    # Check and clean stale stateStores
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
          log_warning "Dapr stateStore '${_state_name}' is bound to a different environment — removing to allow idempotent redeploy."
          delete_dapr_resource_with_verify \
            Applications.Dapr/stateStores "${_state_name}" "$GROUP_NAME" "$WORKSPACE_NAME"
        done <<< "$_stale_states"
      fi
    fi
    
    # Check and clean stale pubSubBrokers
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
          log_warning "Dapr pubSubBroker '${_pubsub_name}' is bound to a different environment — removing to allow idempotent redeploy."
          delete_dapr_resource_with_verify \
            Applications.Dapr/pubSubBrokers "${_pubsub_name}" "$GROUP_NAME" "$WORKSPACE_NAME"
        done <<< "$_stale_pubsubs"
      fi
    fi
    
    unset _target_env_id _secret_json _stale_secrets _state_json _stale_states _pubsub_json _stale_pubsubs
  fi

  section "Deploying Radius application"
  AZURE_AD_LOGIN_ENDPOINT="$(az cloud show --query 'endpoints.activeDirectory' -o tsv 2>/dev/null || true)"
  test -n "$AZURE_AD_LOGIN_ENDPOINT" || fail "Unable to determine Microsoft Entra login endpoint from the active Azure cloud."
  AZURE_AD_AUTHORITY="${AZURE_AD_LOGIN_ENDPOINT%/}/${AZURE_TENANT_ID}"
  APP_DEPLOY_ARGS=(
    deploy
    "$REPO_ROOT/infra/radius/app.bicep"
    --parameters "applicationName=${APP_NAME}"
    --parameters "containerRegistry=${CONTAINER_REGISTRY}"
    --parameters "imageTag=${IMAGE_TAG}"
    --parameters "deploymentTarget=${DEPLOYMENT_TARGET}"
    --parameters "useWorkloadIdentity=true"
    --parameters "azureAdAuthority=${AZURE_AD_AUTHORITY}"
    --parameters "azureAdAudience=api://radiusclaim"
  )
  
  # Only pass ghcrImagePullRef if we need a pull secret
  if needs_ghcr_pull_secret && [ -n "${GHCR_TOKEN:-}" ] && [ -n "${GHCR_USERNAME:-}" ]; then
    APP_DEPLOY_ARGS+=(--parameters "ghcrImagePullRef=ghcr-pull-secret")
  fi
  
  rad_deploy_with_recovery "${APP_DEPLOY_ARGS[@]}"

  # Post-deploy RBAC: Assign data-plane roles on recipe-created Azure resources.
  # Radius v0.56 cannot assign RBAC inline (cross-scope module auth failure),
  # so we discover resources from the RG and assign roles to the workload identity.
  section "Assigning data-plane RBAC on recipe-created resources"
_rbac_scope="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
_rbac_principal="${AZURE_PRINCIPAL_ID_CACHED}"

  # Service Bus → Azure Service Bus Data Owner
_sb_id=""
  _sb_id="$(az resource list -g "$RESOURCE_GROUP" --resource-type 'Microsoft.ServiceBus/namespaces' --query '[0].id' -o tsv 2>/dev/null || true)"
  if [ -n "$_sb_id" ]; then
    log_info "Assigning 'Azure Service Bus Data Owner' on Service Bus..."
    az role assignment create --assignee-object-id "$_rbac_principal" --assignee-principal-type ServicePrincipal \
      --role "Azure Service Bus Data Owner" --scope "$_sb_id" --output none 2>/dev/null || true
    log_success "Service Bus RBAC assigned"
  fi

  # Key Vault → Key Vault Secrets User
_kv_id=""
_kv_name=""
_kv_resource_group=""
_kv_contract_json="$(resolve_secret_store_key_vault_contract || true)"
  _kv_id="$(printf '%s' "$_kv_contract_json" | jq -r '.vaultId // empty' 2>/dev/null || true)"
  _kv_name="$(printf '%s' "$_kv_contract_json" | jq -r '.vaultName // empty' 2>/dev/null || true)"
  _kv_resource_group="$(printf '%s' "$_kv_contract_json" | jq -r '.resourceGroup // empty' 2>/dev/null || true)"
  if [ -z "$_kv_name" ]; then
    _kv_name="$(resolve_secret_store_vault_name | tr -d '\r' || true)"
  fi
  [ -n "$_kv_resource_group" ] || _kv_resource_group="$RESOURCE_GROUP"
  if [ -z "$_kv_id" ] && [ -n "$_kv_name" ]; then
    _kv_id="$(az keyvault show --name "$_kv_name" --resource-group "$_kv_resource_group" --query id -o tsv 2>/dev/null || true)"
  fi
  if [ -n "$_kv_id" ]; then
    log_info "Assigning 'Key Vault Secrets User' on Key Vault..."
    az role assignment create --assignee-object-id "$_rbac_principal" --assignee-principal-type ServicePrincipal \
      --role "Key Vault Secrets User" --scope "$_kv_id" --output none 2>/dev/null || true
    log_success "Key Vault RBAC assigned"
  fi

  # WORKAROUND: Radius 0.56 bicep-de NullReferenceException on 3-segment ARM resource types.
  # Child resources for PostgreSQL (database, Entra admin, firewall rules) cannot be declared
  # in the recipe because the ARM template would contain 3-segment types (e.g.
  # Microsoft.DBforPostgreSQL/flexibleServers/databases) which trigger a NPE in
  # UpdateDeploymentResourcesWithScope (RadiusDeploymentEngineHost.cs line 662).
  # The recipe creates only the top-level server; post-deploy Azure CLI commands here
  # configure the database and Entra admin.
  section "PostgreSQL post-deployment configuration (Radius 0.56 child resource workaround)"

  # ── Step 1: Validate that Radius actually deployed the PostgreSQL server ──────────────
  _pg_database="${PG_DATABASE_NAME:-dapr_state}"
  _pg_server_name=""
  _pg_resource_group=""
  _pg_subscription_id=""

  log_info "Validating PostgreSQL deployment from Radius recipe..."

  # Query the Radius stateStore resource to get actual outputResources
  _statestore_json=$("$RAD_BIN" resource show \
    Applications.Dapr/stateStores statestore \
    --application "$APP_NAME" \
    --output json 2>/dev/null || echo "{}")

  # Check if resource exists
  if ! echo "$_statestore_json" | jq -e '.name' &>/dev/null; then
    fail "Radius stateStore resource 'statestore' not found or not deployed. Check 'rad app list' and deployment logs."
  fi

  # Check provisioning state
  _pg_prov_state=$(echo "$_statestore_json" | jq -r '.properties.provisioningState // "Unknown"')
  if [ "$_pg_prov_state" != "Succeeded" ]; then
    fail "Radius stateStore provisioning failed with state: '$_pg_prov_state'. Check 'rad resource show Applications.Dapr/stateStores statestore --application $APP_NAME' for details."
  fi

  # Extract PostgreSQL ARM resource ID from outputResources
  _pg_resource_id=$(echo "$_statestore_json" | jq -r '
    [.properties.status.outputResources[]? | .id]
    | map(select(test("/Microsoft.DBforPostgreSQL/flexibleServers/[^/]+$")))
    | .[0] // empty
  ')

  if [ -z "$_pg_resource_id" ]; then
    fail "Radius stateStore deployed but no PostgreSQL resource found in outputResources. Recipe may be misconfigured. Check 'rad resource show Applications.Dapr/stateStores statestore --application $APP_NAME' | jq '.properties.status.outputResources'"
  fi

  # Parse ARM resource ID to extract subscription, resource group, and server name
  # Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.DBforPostgreSQL/flexibleServers/{name}
  if [[ "$_pg_resource_id" =~ /subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft.DBforPostgreSQL/flexibleServers/([^/]+)$ ]]; then
    _pg_subscription_id="${BASH_REMATCH[1]}"
    _pg_resource_group="${BASH_REMATCH[2]}"
    _pg_server_name="${BASH_REMATCH[3]}"
  else
    fail "Radius stateStore outputResources contains invalid PostgreSQL ARM ID: '$_pg_resource_id'"
  fi

  log_info "PostgreSQL server from Radius: subscription=$_pg_subscription_id, rg=$_pg_resource_group, server=$_pg_server_name"

  # ── Step 2: Validate that the Azure PostgreSQL server actually exists ───────────────
  _pg_show_output=""
  _pg_show_err=""
  if ! _pg_show_output=$(az postgres flexible-server show \
    --subscription "$_pg_subscription_id" \
    --resource-group "$_pg_resource_group" \
    --name "$_pg_server_name" \
    --output json 2>&1); then
    _pg_show_err="$_pg_show_output"
    if [[ "$_pg_show_err" == *"ResourceNotFound"* ]] || [[ "$_pg_show_err" == *"was not found"* ]]; then
      fail "PostgreSQL server '$_pg_server_name' in resource group '$_pg_resource_group' does not exist in Azure. Radius is tracking a non-existent or deleted server. Check recent Azure resource deletions."
    elif [[ "$_pg_show_err" == *"InvalidParameterValue"* ]] || [[ "$_pg_show_err" == *"does not match"* ]]; then
      fail "PostgreSQL server '$_pg_server_name' not found in the expected location (subscription: $_pg_subscription_id, RG: $_pg_resource_group). Radius outputResources may be stale or pointing to wrong region/RG."
    else
      fail "Failed to validate PostgreSQL server '$_pg_server_name' in Azure: $([[ ${#_pg_show_err} -gt 200 ]] && echo "${_pg_show_err:0:200}..." || echo "$_pg_show_err")"
    fi
  fi

  _pg_state=$(echo "$_pg_show_output" | jq -r '.state // "Unknown"')
  if [ "$_pg_state" != "Ready" ]; then
    log_warning "PostgreSQL server state is '$_pg_state' (expected 'Ready'). Waiting up to 300s..."
    _pg_wait_max=300
    _pg_wait_elapsed=0
    while [ "$_pg_wait_elapsed" -lt "$_pg_wait_max" ]; do
      _pg_state=$(az postgres flexible-server show \
        --subscription "$_pg_subscription_id" \
        --resource-group "$_pg_resource_group" \
        --name "$_pg_server_name" \
        --query 'state' -o tsv 2>/dev/null || echo "Unknown")
      if [ "$_pg_state" = "Ready" ]; then
        log_success "PostgreSQL server became ready."
        break
      fi
      log_info "  PostgreSQL server state: $_pg_state. Waiting 15s..."
      sleep 15
      _pg_wait_elapsed=$((_pg_wait_elapsed + 15))
    done
    if [ "$_pg_state" != "Ready" ]; then
      fail "PostgreSQL server '$_pg_server_name' did not become ready within ${_pg_wait_max}s. Current state: '$_pg_state'"
    fi
  fi
  log_success "PostgreSQL server '$_pg_server_name' is ready."

  # ── Step 3: Configure database and Entra admin (idempotent post-deploy) ──────────────
  log_info "Creating PostgreSQL database '$_pg_database'..."
  _db_create_err=""
  if ! _db_create_err=$(az postgres flexible-server db create \
    --subscription "$_pg_subscription_id" \
    --resource-group "$_pg_resource_group" \
    --server-name "$_pg_server_name" \
    --database-name "$_pg_database" \
    --output none 2>&1); then
    # Only suppress "already exists" errors; fail on other errors
    if [[ "$_db_create_err" == *"already exists"* ]] || [[ "$_db_create_err" == *"AlreadyExists"* ]]; then
      log_info "Database '$_pg_database' already exists (idempotent)."
    else
      fail "Failed to create PostgreSQL database '$_pg_database': $([[ ${#_db_create_err} -gt 200 ]] && echo "${_db_create_err:0:200}..." || echo "$_db_create_err")"
    fi
  else
    log_success "PostgreSQL database '$_pg_database' created."
  fi

  # Register the Dapr workload identity as Entra admin (idempotent)
  log_info "Registering Entra admin '$MANAGED_IDENTITY_NAME' (object ID: ${AZURE_PRINCIPAL_ID_CACHED})..."
  _admin_create_err=""
  if ! _admin_create_err=$(az postgres flexible-server microsoft-entra-admin create \
    --subscription "$_pg_subscription_id" \
    --resource-group "$_pg_resource_group" \
    --server-name "$_pg_server_name" \
    --object-id "$AZURE_PRINCIPAL_ID_CACHED" \
    --display-name "$MANAGED_IDENTITY_NAME" \
    --type ServicePrincipal \
    --output none 2>&1); then
    # Only suppress "already exists" errors; fail on other errors
    if [[ "$_admin_create_err" == *"already exists"* ]] || [[ "$_admin_create_err" == *"AlreadyExists"* ]]; then
      log_info "Entra admin already exists (idempotent)."
    else
      fail "Failed to register Entra admin: $([[ ${#_admin_create_err} -gt 200 ]] && echo "${_admin_create_err:0:200}..." || echo "$_admin_create_err")"
    fi
  else
    log_success "PostgreSQL Entra admin registered."
  fi

  # ── Step 4: Add AllowAzureServices firewall rule (idempotent) ────────────────────────
  # The recipe cannot create child resources (firewallRules) due to Radius 0.56 NPE on
  # 3-segment ARM types. This mirrors the allowAzureServices=true default in the Radius
  # environment bicep. Skip with --pg-no-allow-azure-services for private-endpoint setups.
  if [ "$PG_ALLOW_AZURE_SERVICES" = true ]; then
    log_info "Adding AllowAzureServices firewall rule to PostgreSQL server (allows AKS outbound)..."
    _fw_err=""
    if ! _fw_err=$(az postgres flexible-server firewall-rule create \
      --subscription "$_pg_subscription_id" \
      --resource-group "$_pg_resource_group" \
      --name "$_pg_server_name" \
      --rule-name AllowAzureServices \
      --start-ip-address 0.0.0.0 \
      --end-ip-address 0.0.0.0 \
      --output none 2>&1); then
      if [[ "$_fw_err" == *"already exists"* ]] || [[ "$_fw_err" == *"AlreadyExists"* ]]; then
        log_info "AllowAzureServices firewall rule already exists (idempotent)."
      else
        log_warning "Could not create AllowAzureServices firewall rule: $([[ ${#_fw_err} -gt 200 ]] && echo "${_fw_err:0:200}..." || echo "$_fw_err")"
        log_warning "PostgreSQL connections from AKS may time out. Pass --pg-no-allow-azure-services to suppress this step."
      fi
    else
      log_success "AllowAzureServices firewall rule added."
    fi
    unset _fw_err
  else
    log_info "Skipping AllowAzureServices firewall rule (--pg-no-allow-azure-services set)."
  fi

fi

if [ "$SKIP_APP_DEPLOY" = false ]; then
  section "Wiring GHCR pull secret to service account"
  wait_for_namespace "$WORKLOAD_NAMESPACE"
  patch_pull_secret_to_serviceaccount "$WORKLOAD_NAMESPACE"

  section "Waiting for workloads"
  wait_for_deployment expense-api
  wait_for_deployment workflow-engine
  wait_for_deployment notification-svc
fi

if [ "$SKIP_COMPONENT_REFRESH" = false ]; then
  # ── Phase 1: Radius recipes provision Azure resources (storage, service bus, key vault)
  # ── Phase 2: Bootstrap creates Kubernetes Dapr Component CRDs from recipe outputs
  #
  # This two-phase approach is necessary because:
  # 1. Radius recipes deploy infrastructure and store connection metadata
  # 2. Dapr Component CRDs must be created separately in Kubernetes from that metadata
  # 3. Without this step, workload pods have Dapr sidecars but no components to load
  
  section "Creating Dapr Component CRDs from Radius recipe outputs"
  wait_for_namespace "$WORKLOAD_NAMESPACE"
  
  apply_components_cmd="$SCRIPT_DIR/apply-dapr-components-from-recipes.sh"
  apply_components_args=(
    --environment "$ENV_NAME"
    --application "$APP_NAME"
    --namespace "$WORKLOAD_NAMESPACE"
    --tenant-id "${AZURE_TENANT_ID}"
    --client-id "${AZURE_CLIENT_ID_CACHED}"
    --dapr-pg-user "${MANAGED_IDENTITY_NAME}"
  )
  
  if ! run_cmd "$apply_components_cmd" "${apply_components_args[@]}"; then
    fail "Failed to create Dapr components from recipe outputs. Verify Radius recipes succeeded and output valid resourceMetadata.dapr."
  fi
  
  section "Annotating service accounts for workload identity"
  annotate_cmd="$SCRIPT_DIR/annotate-service-accounts.sh"
  annotate_args=(
    --namespace "$WORKLOAD_NAMESPACE"
    --client-id "$AZURE_CLIENT_ID_CACHED"
    --verify-components
  )
  run_cmd "$annotate_cmd" "${annotate_args[@]}"

  verify_components_present

  section "Restarting workloads so sidecars pick up components"
  run_cmd kubectl rollout restart deployment/expense-api deployment/workflow-engine deployment/notification-svc -n "$WORKLOAD_NAMESPACE"
  wait_for_deployment expense-api
  wait_for_deployment workflow-engine
  wait_for_deployment notification-svc
  wait_for_sidecar_log expense-api "Component loaded: statestore"
  wait_for_sidecar_log workflow-engine "Component loaded: pubsub"
fi

if [ "$SKIP_VALIDATION" = false ]; then
  section "Validating the deployed app"
  if [ -n "$VALIDATION_URL" ]; then
    VALIDATION_BASE_URL="$(normalize_url "$VALIDATION_URL")"
  elif gateway_url="$(get_gateway_url 2>/dev/null || true)"; [ -n "$gateway_url" ] && wait_for_healthz "$gateway_url"; then
    VALIDATION_BASE_URL="$gateway_url"
  else
    log_warning "Public gateway is not ready yet; falling back to kubectl port-forward for validation."
    start_port_forward
  fi

  log_info "Running validation against ${VALIDATION_BASE_URL}"
  run_cmd "$SCRIPT_DIR/validate-deployment.sh" "$VALIDATION_BASE_URL"
fi

section "Bootstrap complete"
log_success "RadiusClaim bootstrap path is ready."
echo "Environment namespace : ${KUBERNETES_NAMESPACE}"
echo "Workload namespace    : ${WORKLOAD_NAMESPACE}"
echo "Recipe registry/tag   : ${RECIPE_REGISTRY}:${RECIPE_TAG}"
echo "Image registry/tag    : ${CONTAINER_REGISTRY}:${IMAGE_TAG}"
if [ -n "$VALIDATION_BASE_URL" ]; then
  echo "Validated URL         : ${VALIDATION_BASE_URL}"
elif gateway_url="$(get_gateway_url 2>/dev/null || true)"; [ -n "$gateway_url" ]; then
  echo "Gateway URL           : ${gateway_url}"
fi

if [ "$RESOURCE_GROUP_CREATED" = true ]; then
  log_info "Bootstrap created Azure resource group '${RESOURCE_GROUP}'."
fi

if [ "$DRY_RUN" = true ]; then
  log_info "Dry run complete. Re-run without --dry-run to execute the plan."
fi

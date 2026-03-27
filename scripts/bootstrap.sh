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

APP_NAME="radiusclaim"
ENV_NAME="azure"
GROUP_NAME="radiusclaim-group"
WORKSPACE_NAME="radiusclaim-workspace"
KUBERNETES_NAMESPACE="radiusclaim-azure"
RESOURCE_GROUP=""
LOCATION="belgiumcentral"
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
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-radiusclaim-aks}"
DRY_RUN=false
YES=false
SKIP_APP_DEPLOY=false
SKIP_COMPONENT_REFRESH=false
SHOULD_REGISTER_AZURE_CREDENTIAL=false
SHOULD_PUBLISH_RECIPES=false
CREATE_SPN=false
SETUP_WORKLOAD_IDENTITY=false
RESOURCE_GROUP_CREATED=false
PORT_FORWARD_PID=""
VALIDATION_BASE_URL=""

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
  --dry-run                     Print the planned mutations without executing them
  --yes                         Accept confirmation prompts non-interactively
  --help                        Show this help message

Required Azure auth env vars when bootstrap must register Radius credentials:
  Service principal mode: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID
  Workload identity mode: AZURE_CLIENT_ID, AZURE_TENANT_ID
Optional override for data-plane RBAC:
  AZURE_PRINCIPAL_ID (Microsoft Entra object ID for the client ID above)
Optional GHCR pull secret (required for private GHCR images on AKS):
  GHCR_USERNAME  GitHub username for the pull secret (e.g. wesback)
  GHCR_TOKEN     GitHub PAT with read:packages scope

Behavior note:
  For Azure-backed platform-secrets, bootstrap preflights the deterministic Key Vault
  name. If the vault is soft-deleted and recoverable back into this deployment scope,
  bootstrap restores it; otherwise it fails early with actionable guidance.
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

fetch_env_id() {
  "$RAD_BIN" env show "$ENV_NAME" -o json 2>/dev/null \
    | sed -n '/^{/,$p' \
    | jq -r '.id // empty' 2>/dev/null || true
}

radius_azure_credential_registered() {
  "$RAD_BIN" credential list 2>/dev/null | grep -qi 'azure'
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
  local resolved_id
  resolved_id="$(az ad sp show --id "${AZURE_CLIENT_ID}" --query id -o tsv 2>/dev/null || true)"
  
  if [ -n "$resolved_id" ]; then
    echo "$resolved_id"
    return 0
  fi

  # Service principal lookup failed — provide diagnostic
  echo >&2 "⚠️  Cannot resolve principal ID via service principal lookup."
  echo >&2 "    AZURE_CLIENT_ID is set to: ${AZURE_CLIENT_ID}"
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

resolve_app_secret_vault_name() {
  local environment_id="$1"
  local deployment_name="bootstrap-secretstore-name-${ENV_NAME}"

  az deployment group create \
    --name "$deployment_name" \
    --resource-group "$RESOURCE_GROUP" \
    --mode Incremental \
    --only-show-errors \
    --template-file /dev/stdin \
    --parameters "applicationName=${APP_NAME}" "environmentId=${environment_id}" \
    --query 'properties.outputs.secretVaultName.value' \
    -o tsv <<'EOF'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "applicationName": {
      "type": "string"
    },
    "environmentId": {
      "type": "string"
    }
  },
  "resources": [],
  "outputs": {
    "secretVaultName": {
      "type": "string",
      "value": "[format('ce-{0}', take(uniqueString(parameters('applicationName'), parameters('environmentId'), 'platform-secrets'), 20))]"
    }
  }
}
EOF
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
  local attempt

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  for attempt in $(seq 1 30); do
    if az keyvault show --name "$vault_name" --resource-group "$RESOURCE_GROUP" --query name -o tsv >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done

  fail "Timed out waiting for restored Key Vault '${vault_name}' in resource group '${RESOURCE_GROUP}'."
}

ensure_azure_secret_store_ready() {
  local secret_store_recipe
  local environment_id
  local secret_vault_name
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

  environment_id="$(fetch_env_id)"
  [ -n "$environment_id" ] || fail "Could not determine the current Radius environment ID needed to preflight the Azure-backed secret store."

  secret_vault_name="$(resolve_app_secret_vault_name "$environment_id" | tr -d '\r')"
  [ -n "$secret_vault_name" ] || fail "Could not resolve the deterministic Key Vault name for 'platform-secrets'."

  section "Preflighting Azure-backed secret store"
  log_info "platform-secrets maps to Key Vault '${secret_vault_name}'."

  if az keyvault show --name "$secret_vault_name" --resource-group "$RESOURCE_GROUP" --query name -o tsv >/dev/null 2>&1; then
    log_success "Key Vault '${secret_vault_name}' already exists in '${RESOURCE_GROUP}'."
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

  restore_message="Key Vault '${secret_vault_name}' is currently soft-deleted in '${RESOURCE_GROUP}'"
  if [ -n "$deleted_purge_date" ]; then
    restore_message="${restore_message} (scheduled purge: ${deleted_purge_date})"
  fi
  restore_message="${restore_message}. Restore it now so bootstrap can reuse the Azure-backed secret store"

  if ! prompt_confirm "$restore_message"; then
    fail "Bootstrap cannot continue until the deleted Key Vault '${secret_vault_name}' is restored, purged, or the Radius environment name changes."
  fi

  section "Recovering soft-deleted Key Vault"
  run_cmd az keyvault recover --name "$secret_vault_name" --location "$deleted_location" --output none
  wait_for_key_vault_recovery "$secret_vault_name"
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

  fail "Dapr sidecar for '${deployment}' did not report '${needle}'."
}

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
actionable_file "$SCRIPT_DIR/deploy-dapr-components-workload-identity.sh"
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
  if [ -z "${GHCR_TOKEN:-}" ] || [ -z "${GHCR_USERNAME:-}" ]; then
    log_warning "GHCR_TOKEN and/or GHCR_USERNAME are not set."
    log_warning "These are needed to publish recipes and create the app image pull secret."
    log_warning "Set them or authenticate with 'gh auth login' to auto-populate:"
    log_warning "  export GHCR_USERNAME=<github-username>"
    log_warning "  export GHCR_TOKEN=<PAT-with-write:packages>"
  fi
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

AZURE_PRINCIPAL_ID_FOR_RBAC="$(resolve_azure_principal_id)"
if [ -n "$AZURE_PRINCIPAL_ID_FOR_RBAC" ]; then
  ensure_radius_recipe_rbac "$AZURE_SUBSCRIPTION_ID" "$RESOURCE_GROUP" "$AZURE_PRINCIPAL_ID_FOR_RBAC"
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

AZURE_AUTH_MODE_RESOLVED="$(resolve_azure_auth_mode)"

# Enable OIDC issuer + workload identity on AKS if requested (must run before
# credential registration so the cluster is ready for wi mode).
if [ "$SETUP_WORKLOAD_IDENTITY" = true ]; then
  section "Enabling OIDC issuer and workload identity on AKS cluster"
  run_cmd az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --enable-oidc-issuer \
    --enable-workload-identity
  # Force wi mode if not already set
  if [ "$AZURE_AUTH_MODE" = "auto" ]; then
    AZURE_AUTH_MODE="wi"
    AZURE_AUTH_MODE_RESOLVED="wi"
  fi
fi
test -n "${AZURE_CLIENT_ID:-}" || fail "AZURE_CLIENT_ID is required for the Microsoft Entra statestore path."
test -n "${AZURE_TENANT_ID:-}" || fail "AZURE_TENANT_ID is required for the Microsoft Entra statestore path."
AZURE_PRINCIPAL_ID_RESOLVED="$(resolve_azure_principal_id)"
test -n "$AZURE_PRINCIPAL_ID_RESOLVED" || fail "Could not resolve the Microsoft Entra principal object ID. See diagnostics above for resolution steps."
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

ENV_DEPLOY_ARGS=(
  deploy
  "$REPO_ROOT/infra/radius/environments/azure-radius.bicep"
  --parameters "@${REPO_ROOT}/infra/radius/environments/azure-radius.parameters.json"
  --parameters "environmentName=${ENV_NAME}"
  --parameters "kubernetesNamespace=${KUBERNETES_NAMESPACE}"
  --parameters "azureProviderScope=/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
  --parameters "location=${LOCATION}"
  --parameters "daprAzureClientId=${AZURE_CLIENT_ID}"
  --parameters "daprAzurePrincipalId=${AZURE_PRINCIPAL_ID_RESOLVED}"
  --parameters "daprAzureTenantId=${AZURE_TENANT_ID}"
  --parameters "daprAzurePrincipalType=ServicePrincipal"
  --parameters "recipeRegistry=${RECIPE_REGISTRY}"
  --parameters "recipeTag=${RECIPE_TAG}"
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

  section "Deploying Radius application"
  APP_DEPLOY_ARGS=(
    deploy
    "$REPO_ROOT/infra/radius/app.bicep"
    --parameters "applicationName=${APP_NAME}"
    --parameters "containerRegistry=${CONTAINER_REGISTRY}"
    --parameters "imageTag=${IMAGE_TAG}"
    --parameters "deploymentTarget=${DEPLOYMENT_TARGET}"
    --parameters "useWorkloadIdentity=true"
    --parameters "ghcrImagePullRef=ghcr-pull-secret"
  )
  run_cmd "$RAD_BIN" "${APP_DEPLOY_ARGS[@]}"
fi

if [ "$SKIP_APP_DEPLOY" = false ]; then
  section "Waiting for workloads"
  wait_for_namespace "$WORKLOAD_NAMESPACE"
  wait_for_deployment expense-api
  wait_for_deployment workflow-engine
  wait_for_deployment notification-svc
fi

if [ "$SKIP_COMPONENT_REFRESH" = false ]; then
  section "Backfilling Dapr components"
  wait_for_namespace "$WORKLOAD_NAMESPACE"
  run_cmd env RAD_BIN="$RAD_BIN" "$SCRIPT_DIR/deploy-dapr-components-workload-identity.sh" \
    --app-name "$APP_NAME" \
    --env-name "$ENV_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER_NAME" \
    --namespace "$WORKLOAD_NAMESPACE"

  verify_components_present

  section "Restarting workloads so sidecars pick up backfilled components"
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

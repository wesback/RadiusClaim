#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
RAD_BIN="${RAD_BIN:-rad}"
source "${SCRIPT_DIR}/lib/platform-common.sh"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
APP_NAME="radiusclaim"
ENV_NAME="azure"
GROUP_NAME="radiusclaim-group"
WORKSPACE_NAME="radiusclaim-workspace"
KUBERNETES_NAMESPACE="radiusclaim-azure"
RESOURCE_GROUP="radiusclaim-rg"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-}"
INCLUDE_RESOURCE_GROUP=false
INCLUDE_SERVICE_PRINCIPALS=false
INCLUDE_GHCR_ARTIFACTS=false
INCLUDE_MANAGED_IDENTITY=false
MI_NAME="radiusclaim-workload-identity"
GHCR_OWNER_OVERRIDE=""
GHCR_REPO_OVERRIDE=""
DRY_RUN=false
YES=false

# Service principal app registration display names created by bootstrap
SP_RADIUS="radiusclaim-radius-sp"
SP_GITHUB="radiusclaim-github-actions"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<USAGE
Usage: ./scripts/teardown.sh [options]

Tears down RadiusClaim resources created by bootstrap.sh and prepare-cluster.sh.
Deletes Radius objects, Kubernetes namespaces, and Azure resources in the correct
dependency order. Safe to run multiple times (idempotent).

Optional:
  --resource-group <name>           Azure resource group (default: ${RESOURCE_GROUP})
  --kube-context <ctx>              Kubernetes context (default: current context)
  --aks-cluster-name <name>         AKS cluster name to delete (default: none; optional)
  --workspace-name <name>           Radius workspace name (default: ${WORKSPACE_NAME})
  --workspace <name>                Alias for --workspace-name (deprecated)
  --group-name <name>               Radius group name (default: ${GROUP_NAME})
  --app-name <name>                 Radius application name (default: ${APP_NAME})
  --env-name <name>                 Radius environment name (default: ${ENV_NAME})
  --kubernetes-namespace <ns>       Radius environment namespace (default: ${KUBERNETES_NAMESPACE})
  --include-resource-group          Delete the entire Azure resource group (default: delete individual resources only)
  --include-service-principals      Also delete service principal app registrations
  --include-ghcr-artifacts          Also delete GHCR container/recipe images (requires gh CLI)
  --include-managed-identity        Also delete the managed identity '${MI_NAME}' and its federated credentials
  --ghcr-owner <owner>              GHCR owner (default: derived from git remote)
  --ghcr-repo <repo>                GHCR repo (default: derived from git remote)
  --dry-run                         Print what would be deleted without executing
  --yes                             Skip confirmation prompts
  --help                            Show this help message

Deletion order:
  1. Radius application, environment, workspace, group
  2. Kubernetes namespaces (workload, then environment)
  3. Azure role assignments on resources in the resource group
  4. AKS cluster (only if --aks-cluster-name is provided)
  5. Azure resources (storage, service bus, key vault, ACR)
  6. Azure resource group (only with --include-resource-group)
  7. Service principal app registrations (only with --include-service-principals)
USAGE
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --kube-context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --aks-cluster-name)
      AKS_CLUSTER_NAME="$2"
      shift 2
      ;;
    --workspace-name)
      WORKSPACE_NAME="$2"
      shift 2
      ;;
    --workspace)
      log_warning "--workspace is deprecated, use --workspace-name"
      WORKSPACE_NAME="$2"
      shift 2
      ;;
    --group-name)
      GROUP_NAME="$2"
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
    --kubernetes-namespace|--namespace)
      KUBERNETES_NAMESPACE="$2"
      shift 2
      ;;
    --include-resource-group)
      INCLUDE_RESOURCE_GROUP=true
      shift
      ;;
    --include-service-principals)
      INCLUDE_SERVICE_PRINCIPALS=true
      shift
      ;;
    --include-ghcr-artifacts)
      INCLUDE_GHCR_ARTIFACTS=true
      shift
      ;;
    --include-managed-identity)
      INCLUDE_MANAGED_IDENTITY=true
      shift
      ;;
    --ghcr-owner)
      GHCR_OWNER_OVERRIDE="$2"
      shift 2
      ;;
    --ghcr-repo)
      GHCR_REPO_OVERRIDE="$2"
      shift 2
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

# Derived values (must match bootstrap.sh convention)
WORKLOAD_NAMESPACE="${KUBERNETES_NAMESPACE}-${APP_NAME}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
kubectl_cmd() {
  local args=("$@")
  if [ -n "$KUBE_CONTEXT" ]; then
    kubectl --context "$KUBE_CONTEXT" "${args[@]}"
  else
    kubectl "${args[@]}"
  fi
}

resource_exists_in_rg() {
  local resource_type="$1"
  az resource list --resource-group "$RESOURCE_GROUP" \
    --resource-type "$resource_type" --query "[].id" -o tsv 2>/dev/null | grep -q .
}

rad_workspace_exists() {
  "$RAD_BIN" workspace list 2>/dev/null | grep -q "$WORKSPACE_NAME"
}

rad_app_exists() {
  "$RAD_BIN" app list -w "$WORKSPACE_NAME" 2>/dev/null | grep -q "$APP_NAME"
}

rad_env_exists() {
  "$RAD_BIN" env list -w "$WORKSPACE_NAME" 2>/dev/null | grep -q "$ENV_NAME"
}

rad_group_exists() {
  "$RAD_BIN" group list -w "$WORKSPACE_NAME" 2>/dev/null | grep -q "$GROUP_NAME"
}

namespace_exists() {
  kubectl_cmd get namespace "$1" >/dev/null 2>&1
}

rg_exists() {
  az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null
}

aks_cluster_exists() {
  az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null
}

sp_app_id_by_name() {
  # macOS ships without GNU timeout; fall back to gtimeout (brew coreutils) then no timeout
  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout 20"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout 20"
  fi
  $timeout_cmd az ad app list --display-name "$1" --query "[0].appId" -o tsv 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Phase functions
# ---------------------------------------------------------------------------
delete_radius_resources() {
  section "Radius resources"

  # 1. Application
  if rad_workspace_exists && rad_app_exists; then
    log_info "Deleting Radius application '${APP_NAME}' ..."
    run_cmd "$RAD_BIN" app delete "$APP_NAME" -w "$WORKSPACE_NAME" -y
    log_success "Radius application '${APP_NAME}' deleted"
  else
    log_info "Radius application '${APP_NAME}' not found — skipping"
  fi

  # 2. Environment
  if rad_workspace_exists && rad_env_exists; then
    log_info "Deleting Radius environment '${ENV_NAME}' ..."
    run_cmd "$RAD_BIN" env delete "$ENV_NAME" -w "$WORKSPACE_NAME" -y
    log_success "Radius environment '${ENV_NAME}' deleted"
  else
    log_info "Radius environment '${ENV_NAME}' not found — skipping"
  fi

  # 3. Group
  if rad_workspace_exists && rad_group_exists; then
    log_info "Deleting Radius group '${GROUP_NAME}' ..."
    run_cmd "$RAD_BIN" group delete "$GROUP_NAME" -w "$WORKSPACE_NAME"
    log_success "Radius group '${GROUP_NAME}' deleted"
  else
    log_info "Radius group '${GROUP_NAME}' not found — skipping"
  fi

  # 4. Workspace
  if rad_workspace_exists; then
    log_info "Deleting Radius workspace '${WORKSPACE_NAME}' ..."
    run_cmd "$RAD_BIN" workspace delete "$WORKSPACE_NAME" -y
    log_success "Radius workspace '${WORKSPACE_NAME}' deleted"
  else
    log_info "Radius workspace '${WORKSPACE_NAME}' not found — skipping"
  fi
}

delete_kubernetes_namespaces() {
  section "Kubernetes namespaces"

  for ns in "$WORKLOAD_NAMESPACE" "$KUBERNETES_NAMESPACE"; do
    if namespace_exists "$ns"; then
      log_info "Deleting namespace '${ns}' ..."
      run_cmd kubectl_cmd delete namespace "$ns" --wait=false
      log_success "Namespace '${ns}' deletion initiated"
    else
      log_info "Namespace '${ns}' does not exist — skipping"
    fi
  done
}

delete_azure_role_assignments() {
  section "Azure role assignments in '${RESOURCE_GROUP}'"

  if ! rg_exists; then
    log_info "Resource group '${RESOURCE_GROUP}' does not exist — skipping role assignments"
    return 0
  fi

  local scope
  scope="/subscriptions/$(az account show --query id -o tsv 2>/dev/null)/resourceGroups/${RESOURCE_GROUP}"

  local assignment_ids
  assignment_ids="$(az role assignment list --scope "$scope" --query "[].id" -o tsv 2>/dev/null || true)"

  if [ -z "$assignment_ids" ]; then
    log_info "No role assignments found on '${RESOURCE_GROUP}' — skipping"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$assignment_ids" | wc -l | tr -d ' ')"
  log_info "Found ${count} role assignment(s) to remove"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    run_cmd az role assignment delete --ids "$id" --yes 2>/dev/null || true
  done <<< "$assignment_ids"

  log_success "Role assignments on '${RESOURCE_GROUP}' removed"
}

delete_managed_identity() {
  section "Managed identity '${MI_NAME}'"

  if ! rg_exists; then
    log_info "Resource group '${RESOURCE_GROUP}' does not exist — skipping managed identity"
    return 0
  fi

  local mi_id
  mi_id="$(az identity show --name "$MI_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || true)"

  if [ -z "$mi_id" ]; then
    log_info "Managed identity '${MI_NAME}' not found in '${RESOURCE_GROUP}' — skipping"
    return 0
  fi

  # Federated credentials are deleted automatically when the MI is deleted,
  # but list them first so the operator can see what was cleaned up.
  local fed_count
  fed_count="$(az identity federated-credential list --identity-name "$MI_NAME" --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")"
  [ "$fed_count" -gt 0 ] && log_info "ℹ Removing ${fed_count} federated credential(s) with managed identity"

  log_info "Deleting managed identity '${MI_NAME}' ..."
  run_cmd az identity delete --name "$MI_NAME" --resource-group "$RESOURCE_GROUP"
  log_success "Managed identity '${MI_NAME}' deleted"
}

delete_aks_cluster() {
  section "AKS cluster '${AKS_CLUSTER_NAME}'"

  if [ -z "$AKS_CLUSTER_NAME" ]; then
    log_info "AKS cluster name not provided — skipping AKS deletion"
    return 0
  fi

  if ! rg_exists; then
    log_info "Resource group '${RESOURCE_GROUP}' does not exist — skipping AKS cluster"
    return 0
  fi

  if ! aks_cluster_exists; then
    log_info "AKS cluster '${AKS_CLUSTER_NAME}' does not exist — skipping"
    return 0
  fi

  log_info "Deleting AKS cluster '${AKS_CLUSTER_NAME}' (this may take several minutes) ..."
  run_cmd az aks delete --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --yes --no-wait
  log_success "AKS cluster '${AKS_CLUSTER_NAME}' deletion initiated"
}

delete_azure_resources() {
  section "Azure resources in '${RESOURCE_GROUP}'"

  if ! rg_exists; then
    log_info "Resource group '${RESOURCE_GROUP}' does not exist — skipping Azure resources"
    return 0
  fi

  # Build exclusion query: skip AKS if --aks-cluster-name not provided
  local query_filter="[]"
  if [ -z "$AKS_CLUSTER_NAME" ]; then
    query_filter="[?type != 'Microsoft.ContainerService/managedClusters']"
  fi

  local all_resources
  all_resources="$(az resource list --resource-group "$RESOURCE_GROUP" --query "${query_filter}" -o json 2>/dev/null || echo "[]")"

  # Check for excluded AKS clusters
  if [ -z "$AKS_CLUSTER_NAME" ]; then
    local aks_clusters
    aks_clusters="$(az resource list --resource-group "$RESOURCE_GROUP" \
      --resource-type "Microsoft.ContainerService/managedClusters" \
      --query "[].name" -o tsv 2>/dev/null || true)"
    
    if [ -n "$aks_clusters" ]; then
      while IFS= read -r cluster_name; do
        [ -n "$cluster_name" ] || continue
        log_info "ℹ Skipping AKS cluster '${cluster_name}' (use --aks-cluster-name to include)"
      done <<< "$aks_clusters"
    fi
  fi

  local resource_ids
  resource_ids="$(echo "$all_resources" | jq -r '.[].id' 2>/dev/null || true)"

  if [ -z "$resource_ids" ]; then
    log_info "No resources found in '${RESOURCE_GROUP}' — skipping"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$resource_ids" | wc -l | tr -d ' ')"
  log_info "Deleting ${count} resource(s) from '${RESOURCE_GROUP}' ..."

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    log_info "  Deleting: ${id##*/}"
    run_cmd az resource delete --ids "$id" --no-wait 2>/dev/null || log_warning "  Could not delete ${id##*/} — may have dependencies or already be deleted"
  done <<< "$resource_ids"

  log_success "Azure resources in '${RESOURCE_GROUP}' deleted"
}

delete_resource_group() {
  section "Azure resource group '${RESOURCE_GROUP}'"

  if ! rg_exists; then
    log_info "Resource group '${RESOURCE_GROUP}' does not exist — skipping"
    return 0
  fi

  log_info "Deleting resource group '${RESOURCE_GROUP}' (this may take several minutes) ..."
  run_cmd az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  log_success "Resource group '${RESOURCE_GROUP}' deletion initiated"
}

delete_service_principals() {
  section "Service principal app registrations"

  for sp_name in "$SP_RADIUS" "$SP_GITHUB"; do
    local app_id
    log_info "Looking up app registration '${sp_name}' ..."
    app_id="$(sp_app_id_by_name "$sp_name")"

    if [ -n "$app_id" ]; then
      log_info "Deleting app registration '${sp_name}' (appId: ${app_id}) ..."
      run_cmd az ad app delete --id "$app_id"
      log_success "App registration '${sp_name}' deleted"
    else
      log_info "App registration '${sp_name}' not found — skipping"
    fi
  done
}

delete_ghcr_artifacts() {
  section "GHCR container and recipe images"

  if ! command -v gh >/dev/null 2>&1; then
    log_warning "gh CLI not found — cannot delete GHCR artifacts. Remove them manually from GitHub Packages."
    return 0
  fi

  # Derive owner/repo from git remote, with override support via --ghcr-owner / --ghcr-repo
  local owner repo
  if [ -n "${GHCR_OWNER_OVERRIDE:-}" ]; then
    owner="$GHCR_OWNER_OVERRIDE"
  else
    local remote
    remote="$(git -C "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" config --get remote.origin.url 2>/dev/null || true)"
    if [[ "$remote" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
      owner="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    else
      owner="wesback"
      log_warning "Could not derive GHCR owner from git remote — falling back to '${owner}'. Use --ghcr-owner to override."
    fi
  fi

  if [ -n "${GHCR_REPO_OVERRIDE:-}" ]; then
    repo="$GHCR_REPO_OVERRIDE"
  else
    local remote
    remote="$(git -C "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" config --get remote.origin.url 2>/dev/null || true)"
    if [[ "$remote" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
      repo="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
    else
      repo="radiusclaim"
      log_warning "Could not derive GHCR repo from git remote — falling back to '${repo}'. Use --ghcr-repo to override."
    fi
  fi

  log_info "GHCR owner: ${owner}, repo: ${repo}"

  local packages=(
    "recipes/state-store"
    "recipes/pubsub"
    "recipes/secrets"
    "expense-api"
    "workflow-engine"
    "notification-svc"
  )

  for pkg in "${packages[@]}"; do
    local full_name="${repo}/${pkg}"
    # URL-encode the package name: forward slashes must be %2F for GitHub API
    local encoded_name="${full_name//\//%2F}"
    log_info "Deleting package versions for '${full_name}' ..."
    if run_cmd gh api -X DELETE "/user/packages/container/${encoded_name}" 2>/dev/null; then
      log_success "Package '${full_name}' deleted"
    else
      log_warning "Could not delete '${full_name}' — may not exist or requires manual removal via GitHub UI"
    fi
  done
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
section "Pre-flight checks"

require_command az
require_command kubectl

if ! az account show --output none 2>/dev/null; then
  log_error "Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi

if ! command -v "$RAD_BIN" >/dev/null 2>&1; then
  log_warning "Radius CLI ('${RAD_BIN}') not found — Radius resource cleanup will be skipped"
  SKIP_RADIUS=true
else
  SKIP_RADIUS=false
fi

if [ -n "$KUBE_CONTEXT" ]; then
  kubectl_cmd cluster-info >/dev/null 2>&1 \
    || log_warning "Cannot reach cluster with context '${KUBE_CONTEXT}' — Kubernetes cleanup may be skipped"
fi

# ---------------------------------------------------------------------------
# Build summary of what will be deleted
# ---------------------------------------------------------------------------
section "Teardown plan"

echo
echo "  Resource group:        ${RESOURCE_GROUP}"
echo "  Kube context:          ${KUBE_CONTEXT:-<current>}"
echo "  Radius workspace:      ${WORKSPACE_NAME}"
echo "  Radius app:            ${APP_NAME}"
echo "  Radius environment:    ${ENV_NAME}"
echo "  Radius group:          ${GROUP_NAME}"
echo "  Env namespace:         ${KUBERNETES_NAMESPACE}"
echo "  Workload namespace:    ${WORKLOAD_NAMESPACE}"
echo "  AKS cluster:           ${AKS_CLUSTER_NAME:-<not specified>}"
echo "  Delete resource group: ${INCLUDE_RESOURCE_GROUP}"
echo "  Delete SPs:            ${INCLUDE_SERVICE_PRINCIPALS}"
echo "  Delete GHCR artifacts: ${INCLUDE_GHCR_ARTIFACTS}"
echo "  Delete managed id:     ${INCLUDE_MANAGED_IDENTITY}"
echo "  Dry run:               ${DRY_RUN}"
echo

if [ "$DRY_RUN" = true ]; then
  log_info "DRY RUN — no resources will be modified"
fi

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = false ]; then
  prompt_confirm "Proceed with teardown?" || { log_info "Aborted."; exit 0; }
fi

# ---------------------------------------------------------------------------
# Execute teardown in dependency order
# ---------------------------------------------------------------------------

# 1 & 2 — Radius application → environment → group → workspace
if [ "$SKIP_RADIUS" = false ]; then
  delete_radius_resources
else
  log_info "Skipping Radius resource cleanup (rad CLI not available)"
fi

# 3 — Kubernetes namespaces
delete_kubernetes_namespaces

# 4 — Azure role assignments
delete_azure_role_assignments

# 5 — AKS cluster (opt-in via --aks-cluster-name)
delete_aks_cluster

# 5a — Managed identity (opt-in, or auto when --include-resource-group since RG deletion removes it anyway)
if [ "$INCLUDE_MANAGED_IDENTITY" = true ] || [ "$INCLUDE_RESOURCE_GROUP" = true ]; then
  delete_managed_identity
fi

# 6 & 7 — Azure resources (individual or entire RG)
if [ "$INCLUDE_RESOURCE_GROUP" = true ]; then
  delete_resource_group
else
  delete_azure_resources
fi

# 8 — Service principals (opt-in)
if [ "$INCLUDE_SERVICE_PRINCIPALS" = true ]; then
  delete_service_principals
fi

# 9 — GHCR artifacts (opt-in)
if [ "$INCLUDE_GHCR_ARTIFACTS" = true ]; then
  delete_ghcr_artifacts
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
section "Teardown complete"

if [ "$DRY_RUN" = true ]; then
  log_success "Dry run finished — no resources were modified"
else
  log_success "RadiusClaim teardown finished"
  if [ -z "$AKS_CLUSTER_NAME" ]; then
    log_info "AKS cluster was not explicitly deleted (pass --aks-cluster-name <name> to delete it)"
  fi
  if [ "$INCLUDE_RESOURCE_GROUP" = false ]; then
    log_info "Resource group '${RESOURCE_GROUP}' was preserved (pass --include-resource-group to delete it)"
  fi
  if [ "$INCLUDE_SERVICE_PRINCIPALS" = false ]; then
    log_info "Service principals were preserved (pass --include-service-principals to delete them)"
  fi
  if [ "$INCLUDE_GHCR_ARTIFACTS" = false ]; then
    log_info "GHCR images/recipes were preserved (pass --include-ghcr-artifacts to delete them)"
  fi
fi

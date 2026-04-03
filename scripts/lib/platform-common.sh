#!/usr/bin/env bash

# Shared project-level defaults.  Callers may override before sourcing or after.
DEFAULT_AKS_CLUSTER_NAME="radiusclaim-aks"
DEFAULT_APP_NAME="radiusclaim"
DEFAULT_ENV_NAME="azure"
DEFAULT_WORKSPACE_NAME="radiusclaim-workspace"
DEFAULT_GROUP_NAME="radiusclaim-group"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

color_enabled() {
  [ -t 1 ]
}

log_info() {
  if color_enabled; then
    echo -e "${BLUE}ℹ${NC} $*"
  else
    echo "[info] $*"
  fi
}

log_success() {
  if color_enabled; then
    echo -e "${GREEN}✓${NC} $*"
  else
    echo "[ok] $*"
  fi
}

log_warning() {
  if color_enabled; then
    echo -e "${YELLOW}⚠${NC} $*"
  else
    echo "[warn] $*"
  fi
}

log_error() {
  if color_enabled; then
    echo -e "${RED}✗${NC} $*" >&2
  else
    echo "[error] $*" >&2
  fi
}

section() {
  echo
  echo "==> $*"
}

fail() {
  log_error "$*"
  exit 1
}

shell_join() {
  local quoted=""
  local arg

  for arg in "$@"; do
    if [ -n "$quoted" ]; then
      quoted+=" "
    fi
    quoted+="$(printf '%q' "$arg")"
  done

  printf '%s\n' "$quoted"
}

run_cmd() {
  if [ "${DRY_RUN:-false}" = true ]; then
    echo "[dry-run] $(shell_join "$@")"
    return 0
  fi

  "$@"
}

prompt_confirm() {
  local message="$1"
  local response

  if [ "${YES:-false}" = true ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    fail "Confirmation required: ${message}. Re-run with --yes to proceed non-interactively."
  fi

  read -r -p "${message} [y/N] " response
  case "$response" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

actionable_file() {
  local path="$1"
  local display="$path"

  if [ -n "${REPO_ROOT:-}" ] && [[ "$display" == "$REPO_ROOT/"* ]]; then
    display="${display#$REPO_ROOT/}"
  fi

  [ -f "$path" ] || fail "Required file not found: ${display}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

control_plane_running() {
  local namespace="$1"
  local label="$2"
  local json

  json="$(kubectl get pods -n "$namespace" -l "$label" -o json 2>/dev/null)" || return 1
  printf '%s' "$json" | jq -e '[.items[] | select(.status.phase == "Running")] | length > 0' >/dev/null 2>&1
}

radius_controller_selector_candidates() {
  printf '%s\n' \
    "app.kubernetes.io/name=controller" \
    "app.kubernetes.io/name=radius-controller-manager"
}

radius_controller_deployment_candidates() {
  printf '%s\n' \
    "controller" \
    "radius-controller-manager"
}

radius_control_plane_running() {
  local namespace="${1:-radius-system}"
  local selector

  for selector in $(radius_controller_selector_candidates); do
    control_plane_running "$namespace" "$selector" && return 0
  done

  return 1
}

find_radius_controller_deployment() {
  local namespace="${1:-radius-system}"
  local deployment

  for deployment in $(radius_controller_deployment_candidates); do
    if kubectl get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
      printf '%s\n' "$deployment"
      return 0
    fi
  done

  return 1
}

rad_version_check() {
  if "$RAD_BIN" version >/dev/null 2>&1; then
    return 0
  fi

  "$RAD_BIN" --version >/dev/null 2>&1 || fail "Radius CLI not responding via '$RAD_BIN'."
}

ensure_control_plane_running() {
  local namespace="$1"
  local label="$2"
  local description="${3:-$2}"
 
  control_plane_running "$namespace" "$label" \
    || fail "Expected a running ${description} pod in namespace '${namespace}' (selector: ${label})."
}

ensure_radius_control_plane_running() {
  local namespace="${1:-radius-system}"

  radius_control_plane_running "$namespace" \
    || fail "Expected a running Radius controller pod in namespace '${namespace}' (selectors: app.kubernetes.io/name=controller | app.kubernetes.io/name=radius-controller-manager)."
}

ensure_radius_workspace_context() {
  local workspace_name="$1"
  local group_name="$2"
  local kube_context="${3:-}"
  local workspace_args

  workspace_args=(workspace create kubernetes "$workspace_name" --force)
  if [ -n "$kube_context" ]; then
    workspace_args+=(--context "$kube_context")
  fi

  section "Radius workspace context"
  if [ "${DRY_RUN:-false}" = true ]; then
    run_cmd "$RAD_BIN" "${workspace_args[@]}"
  else
    run_cmd "$RAD_BIN" "${workspace_args[@]}"
  fi

  run_cmd "$RAD_BIN" workspace switch "$workspace_name"

  if [ "${DRY_RUN:-false}" = true ]; then
    run_cmd "$RAD_BIN" group create "$group_name" -w "$workspace_name"
  else
    "$RAD_BIN" group create "$group_name" -w "$workspace_name" >/dev/null 2>&1 || true
  fi

  run_cmd "$RAD_BIN" group switch "$group_name" -w "$workspace_name"
  log_success "Radius workspace '${workspace_name}' and group '${group_name}' are selected"
}

ensure_radius_recipe_rbac() {
  local subscription_id="${1:-$AZURE_SUBSCRIPTION_ID}"
  local resource_group="$2"
  local sp_object_id="${3:-}"
  
  [ -n "$subscription_id" ] || fail "Azure subscription ID is required for RBAC setup."
  [ -n "$resource_group" ] || fail "Resource group is required for RBAC setup."
  
  if [ -z "$sp_object_id" ]; then
    log_info "Skipping Radius recipe RBAC setup: service principal object ID not provided."
    log_info "Radius recipes that assign roles will require User Access Administrator or Owner on '${resource_group}'."
    return 0
  fi
  
  local scope="/subscriptions/${subscription_id}/resourceGroups/${resource_group}"
  local has_uaa=false
  local has_owner=false
  local has_contributor=false
  
  local assignments
  assignments="$(az role assignment list --assignee "$sp_object_id" --scope "$scope" --query "[].{role:roleDefinitionName}" -o tsv 2>/dev/null || echo "")"
  
  if printf '%s\n' "$assignments" | grep -iqx "User Access Administrator"; then
    has_uaa=true
  fi
  
  if printf '%s\n' "$assignments" | grep -iqx "Owner"; then
    has_owner=true
  fi

  if printf '%s\n' "$assignments" | grep -iqx "Contributor"; then
    has_contributor=true
  fi
  
  if [ "$has_owner" = true ]; then
    log_success "Service principal has Owner on '${resource_group}' (covers resource provisioning and role assignment)"
    return 0
  fi

  # Radius needs Contributor for resource provisioning and User Access Administrator
  # for data-plane RBAC assignments (e.g. Storage Blob Data Contributor).
  if [ "$has_contributor" = false ]; then
    log_info "Granting Contributor role to service principal on '${resource_group}'"
    log_info "This allows Radius recipes to provision Azure resources."
    run_cmd az role assignment create \
      --assignee "$sp_object_id" \
      --role "Contributor" \
      --scope "$scope" \
      --output none
    log_success "Contributor role granted on '${resource_group}'"
  fi

  if [ "$has_uaa" = false ]; then
    log_info "Granting User Access Administrator role to service principal on '${resource_group}'"
    log_info "This allows Radius recipes to assign data-plane roles (e.g., Storage Blob Data Contributor)."
    run_cmd az role assignment create \
      --assignee "$sp_object_id" \
      --role "User Access Administrator" \
      --scope "$scope" \
      --output none
    log_success "User Access Administrator role granted on '${resource_group}'"
  fi

  log_success "Service principal has required permissions on '${resource_group}'"
}

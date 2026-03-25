#!/usr/bin/env bash

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

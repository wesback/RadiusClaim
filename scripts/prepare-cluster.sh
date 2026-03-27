#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
RAD_BIN="${RAD_BIN:-rad}"
source "${SCRIPT_DIR}/lib/platform-common.sh"

RESOURCE_GROUP=""
LOCATION="belgiumcentral"
AKS_CLUSTER_NAME=""
WORKSPACE_NAME="radiusclaim-workspace"
GROUP_NAME="radiusclaim-group"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
AKS_NODE_COUNT=2
AKS_MIN_COUNT=1
AKS_MAX_COUNT=3
CREATE_AKS=false
CREATE_SPN=false
INSTALL_DAPR=false
INSTALL_RADIUS=false
YES=false
DRY_RUN=false

usage() {
  cat <<USAGE
Usage: ./scripts/prepare-cluster.sh [options]

Prepares a Kubernetes cluster for the RadiusClaim AKS/Kubernetes operator path.
This script owns first-time cluster work: AKS creation or verification, kubectl
context setup, Dapr/Radius control-plane installation or preflight, and Radius
workspace/group context. Use ./scripts/bootstrap.sh after this step for the
repeatable app deployment flow.

Required:
  --resource-group <name>       Azure resource group for AKS and recipe-backed services

Optional:
  --location <region>           Azure region for AKS/resource group (default: ${LOCATION})
  --aks-cluster-name <name>     AKS cluster to verify or prepare
  --create-aks                  Create the AKS cluster when it does not exist
  --create-spn                  Create an Azure service principal for Radius (skipped if credentials already set)
  --node-count <count>          Initial AKS node count (default: ${AKS_NODE_COUNT})
  --min-count <count>           AKS autoscaler minimum node count (default: ${AKS_MIN_COUNT})
  --max-count <count>           AKS autoscaler maximum node count (default: ${AKS_MAX_COUNT})
  --install-dapr                Install Dapr on the cluster when missing
  --install-radius              Install Radius on the cluster when missing
  --workspace-name <name>       Radius workspace name (default: ${WORKSPACE_NAME})
  --group-name <name>           Radius group name (default: ${GROUP_NAME})
  --kube-context <context>      kubectl context to use after credentials are set
  --dry-run                     Print the planned mutations without executing them
  --yes                         Accept confirmation prompts non-interactively
  --help                        Show this help message

Notes:
  - Pass --aks-cluster-name with --resource-group to reuse an existing AKS cluster.
  - Pass --create-aks as an explicit gate before the script is allowed to create AKS.
  - On a fresh cluster, pass --install-dapr and --install-radius; without those
    flags the script stays in verification mode for those control planes and
    stops if either one is missing.
  - If you are using Arc-enabled or self-managed Kubernetes, omit --aks-cluster-name
    and make sure kubectl already points at the target cluster (or pass --kube-context).
USAGE
}

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
    --aks-cluster-name)
      AKS_CLUSTER_NAME="$2"
      shift 2
      ;;
    --create-aks)
      CREATE_AKS=true
      shift
      ;;
    --create-spn)
      CREATE_SPN=true
      shift
      ;;
    --node-count)
      AKS_NODE_COUNT="$2"
      shift 2
      ;;
    --min-count)
      AKS_MIN_COUNT="$2"
      shift 2
      ;;
    --max-count)
      AKS_MAX_COUNT="$2"
      shift 2
      ;;
    --install-dapr)
      INSTALL_DAPR=true
      shift
      ;;
    --install-radius)
      INSTALL_RADIUS=true
      shift
      ;;
    --workspace-name)
      WORKSPACE_NAME="$2"
      shift 2
      ;;
    --group-name)
      GROUP_NAME="$2"
      shift 2
      ;;
    --kube-context)
      KUBE_CONTEXT="$2"
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

[ -n "$RESOURCE_GROUP" ] || fail "--resource-group is required."
[ -n "$AKS_CLUSTER_NAME" ] || [ "$CREATE_AKS" = false ] || fail "--create-aks requires --aks-cluster-name."
[ -z "$AKS_CLUSTER_NAME" ] || [ -n "$RESOURCE_GROUP" ] || fail "--aks-cluster-name requires --resource-group."
[ "$AKS_NODE_COUNT" -ge 1 ] || fail "--node-count must be at least 1."
[ "$AKS_MIN_COUNT" -ge 1 ] || fail "--min-count must be at least 1."
[ "$AKS_MAX_COUNT" -ge "$AKS_MIN_COUNT" ] || fail "--max-count must be greater than or equal to --min-count."
[ "$AKS_NODE_COUNT" -ge "$AKS_MIN_COUNT" ] || fail "--node-count must be greater than or equal to --min-count."
[ "$AKS_NODE_COUNT" -le "$AKS_MAX_COUNT" ] || fail "--node-count must be less than or equal to --max-count."

resource_group_exists() {
  [ -n "$RESOURCE_GROUP" ] || return 1
  [ "$(az group exists --name "$RESOURCE_GROUP")" = "true" ]
}

aks_cluster_exists() {
  [ -n "$AKS_CLUSTER_NAME" ] || return 1
  az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --query name -o tsv >/dev/null 2>&1
}

ensure_resource_group() {
  [ -n "$RESOURCE_GROUP" ] || fail "--resource-group is required."

  if resource_group_exists; then
    log_success "Azure resource group '${RESOURCE_GROUP}' already exists"
    return 0
  fi

  prompt_confirm "Resource group '${RESOURCE_GROUP}' does not exist. Create it in '${LOCATION}'" \
    || fail "Cluster preparation requires a resource group before bootstrap can deploy Azure backing services."

  section "Creating Azure resource group"
  run_cmd az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
}

ensure_cluster_admin_for_install() {
  kubectl auth can-i create namespaces 2>/dev/null | grep -qx 'yes' \
    || fail "Current Kubernetes identity cannot create namespaces. Cluster-level prep requires elevated permissions."
  kubectl auth can-i create customresourcedefinitions.apiextensions.k8s.io 2>/dev/null | grep -qx 'yes' \
    || fail "Current Kubernetes identity cannot create CRDs. Cluster-level prep requires elevated permissions."
}

select_kubectl_context() {
  [ -n "$KUBE_CONTEXT" ] || return 0

  if [ "$DRY_RUN" = true ]; then
    run_cmd kubectl config use-context "$KUBE_CONTEXT"
    return 0
  fi

  kubectl config use-context "$KUBE_CONTEXT" >/dev/null 2>&1 \
    || fail "kubectl could not switch to context '${KUBE_CONTEXT}'."
}

resolve_kubectl_context() {
  if [ "$DRY_RUN" = true ]; then
    if [ -n "$KUBE_CONTEXT" ]; then
      echo "$KUBE_CONTEXT"
      return 0
    fi
    if [ -n "$AKS_CLUSTER_NAME" ]; then
      echo "$AKS_CLUSTER_NAME"
      return 0
    fi
    kubectl config current-context 2>/dev/null || echo "<current-context>"
    return 0
  fi

  local current_context
  current_context="$(kubectl config current-context 2>/dev/null || true)"
  [ -n "$current_context" ] || fail "No Kubernetes target is selected. Pass --aks-cluster-name [--create-aks] for AKS, or use --kube-context (or an already configured current kubectl context) for an existing cluster."
  kubectl cluster-info >/dev/null 2>&1 || fail "kubectl cannot reach the current cluster '${current_context}'. Pass --aks-cluster-name [--create-aks] to prepare AKS, or fix/use --kube-context for an existing cluster."
  printf '%s\n' "$current_context"
}

ensure_cluster_target_selected() {
  if [ -n "$AKS_CLUSTER_NAME" ] || [ -n "$KUBE_CONTEXT" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  kubectl config current-context >/dev/null 2>&1 && return 0

  fail "No cluster target is selected. Re-run with --aks-cluster-name [--create-aks] for AKS, or set --kube-context (or a current kubectl context) for an existing cluster."
}

verify_dapr_ready() {
  dapr status -k >/dev/null 2>&1 || return 1
  control_plane_running "dapr-system" "app.kubernetes.io/part-of=dapr"
}

verify_radius_ready() {
  radius_control_plane_running "radius-system"
}

wait_for_radius_rollout() {
  local deployment

  deployment="$(find_radius_controller_deployment "radius-system")" || return 1
  kubectl rollout status "deployment/${deployment}" -n radius-system --timeout=5m >/dev/null 2>&1
}

install_dapr_if_needed() {
  if verify_dapr_ready; then
    log_success "Dapr control plane is ready"
    return 0
  fi

  if [ "$INSTALL_DAPR" = false ]; then
    fail "Dapr control plane is not ready. Install it manually or rerun with --install-dapr."
  fi

  ensure_cluster_admin_for_install
  section "Installing Dapr"
  run_cmd dapr init -k --wait

  if [ "$DRY_RUN" = false ]; then
    verify_dapr_ready || fail "Dapr control plane did not become ready after installation."
  fi
}

install_radius_if_needed() {
  local install_output=""
  local existing_install=false

  if verify_radius_ready; then
    log_success "Radius control plane is ready"
    return 0
  fi

  if [ "$INSTALL_RADIUS" = false ]; then
    fail "Radius control plane is not ready. Install it manually or rerun with --install-radius."
  fi

  ensure_cluster_admin_for_install
  section "Installing Radius"
  if [ "$DRY_RUN" = true ]; then
    run_cmd "$RAD_BIN" install kubernetes --set clusterType=generic
    return 0
  fi

  install_output="$("$RAD_BIN" install kubernetes --set clusterType=generic 2>&1)" || {
    printf '%s\n' "$install_output" >&2
    fail "Radius installation command failed."
  }
  printf '%s\n' "$install_output"

  if printf '%s' "$install_output" | grep -Fq "Found existing Radius installation."; then
    existing_install=true
  fi

  if ! wait_for_radius_rollout || ! verify_radius_ready; then
    if [ "$existing_install" = true ]; then
      fail "Radius is already installed on this cluster, but its control plane is not ready. The script does not auto-repair an existing installation; inspect 'kubectl get deployments,pods -n radius-system' and rerun 'rad install kubernetes --reinstall --set clusterType=generic' if you intend to repair it."
    fi

    fail "Radius control plane did not become ready after installation."
  fi
}

prepare_aks_cluster() {
  [ -n "$AKS_CLUSTER_NAME" ] || return 0

  if aks_cluster_exists; then
    log_success "AKS cluster '${AKS_CLUSTER_NAME}' already exists in '${RESOURCE_GROUP}'"
  else
    [ "$CREATE_AKS" = true ] || fail "AKS cluster '${AKS_CLUSTER_NAME}' does not exist. Re-run with --create-aks to provision it."

    prompt_confirm "AKS cluster '${AKS_CLUSTER_NAME}' does not exist. Create it in '${RESOURCE_GROUP}'" \
      || fail "Cluster preparation stopped before creating AKS."

    section "Creating AKS cluster"
    run_cmd az aks create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$AKS_CLUSTER_NAME" \
      --location "$LOCATION" \
      --node-count "$AKS_NODE_COUNT" \
      --load-balancer-sku standard \
      --enable-managed-identity \
      --network-plugin azure \
      --network-policy azure \
      --enable-cluster-autoscaler \
      --min-count "$AKS_MIN_COUNT" \
      --max-count "$AKS_MAX_COUNT" \
      --generate-ssh-keys \
      --output none
  fi

  section "Configuring kubectl for AKS"
  run_cmd az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --overwrite-existing
}

section "Pre-flight checks"
require_command az
require_command kubectl
require_command jq
require_command dapr
require_command "$RAD_BIN"
actionable_file "$SCRIPT_DIR/bootstrap.sh"
rad_version_check

AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null)"
AZURE_SUBSCRIPTION_NAME="$(az account show --query name -o tsv 2>/dev/null)"
[ -n "$AZURE_SUBSCRIPTION_ID" ] || fail "Azure CLI is not logged in or no subscription is selected."

# Service Principal for Radius Azure provider
section "Azure Service Principal for Radius"
if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_CLIENT_SECRET:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ]; then
  log_success "Using existing Azure service principal credentials (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID)"
else
  if [ "$CREATE_SPN" = false ]; then
    fail "Azure service principal credentials are not set.
Pass --create-spn to create one automatically, or export:
  AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID"
  fi
  
  log_info "Creating Azure service principal for Radius"
  log_info "Radius requires a service principal to provision Azure-backed recipe resources."
  
  # Check if SPN already exists by name
  SPN_NAME="radiusclaim-radius-sp"
  EXISTING_APP_ID="$(az ad sp list --display-name "$SPN_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)"
  
  if [ -n "$EXISTING_APP_ID" ]; then
    log_warning "Service principal '${SPN_NAME}' already exists (App ID: ${EXISTING_APP_ID})"
    log_info "You can reuse it by exporting AZURE_CLIENT_ID and AZURE_CLIENT_SECRET,"
    log_info "or create a new one with a timestamp suffix."
    
    if ! prompt_confirm "Create a new service principal with timestamp suffix instead?"; then
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
    
    # Create new SPN with timestamp suffix
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
  
  # Create the service principal
  log_info "Creating service principal '${SPN_NAME}'..."
  SPN_JSON="$(az ad sp create-for-rbac \
    --name "$SPN_NAME" \
    --role Contributor \
    --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
    --output json)" || fail "Failed to create service principal."
  
  # Parse and export credentials
  export AZURE_CLIENT_ID="$(printf '%s' "$SPN_JSON" | jq -r '.appId')"
  export AZURE_CLIENT_SECRET="$(printf '%s' "$SPN_JSON" | jq -r '.password')"
  export AZURE_TENANT_ID="$(printf '%s' "$SPN_JSON" | jq -r '.tenant')"
  
  [ -n "$AZURE_CLIENT_ID" ] || fail "Failed to parse AZURE_CLIENT_ID from service principal response."
  [ -n "$AZURE_CLIENT_SECRET" ] || fail "Failed to parse AZURE_CLIENT_SECRET from service principal response."
  [ -n "$AZURE_TENANT_ID" ] || fail "Failed to parse AZURE_TENANT_ID from service principal response."
  
  # Print prominent warning with credentials
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
fi

ensure_resource_group
prepare_aks_cluster
ensure_cluster_target_selected

section "Verifying kubectl context"
select_kubectl_context
KUBECTL_CONTEXT="$(resolve_kubectl_context)"
log_success "kubectl context '${KUBECTL_CONTEXT}' is selected"

if [ "$DRY_RUN" = false ]; then
  kubectl get nodes -o name >/dev/null 2>&1 || fail "kubectl cannot list cluster nodes."
fi

section "Cluster control planes"
install_dapr_if_needed
install_radius_if_needed

ensure_radius_workspace_context "$WORKSPACE_NAME" "$GROUP_NAME" "$KUBECTL_CONTEXT"

# Register Azure credentials with Radius control plane
# Radius needs these separately from bicep parameters to authenticate recipe deployments
section "Registering Azure credentials with Radius"
if "$RAD_BIN" credential show azure >/dev/null 2>&1; then
  log_success "Azure credentials are already registered with Radius"
else
  if [ "$DRY_RUN" = true ]; then
    run_cmd "$RAD_BIN" credential register azure sp \
      --client-id "${AZURE_CLIENT_ID}" \
      --client-secret "${AZURE_CLIENT_SECRET}" \
      --tenant-id "${AZURE_TENANT_ID}"
  else
    run_cmd "$RAD_BIN" credential register azure sp \
      --client-id "${AZURE_CLIENT_ID}" \
      --client-secret "${AZURE_CLIENT_SECRET}" \
      --tenant-id "${AZURE_TENANT_ID}"
    log_success "Azure credentials registered with Radius"
  fi
fi

section "Cluster prep complete"
log_success "Cluster preparation is complete. Use bootstrap.sh for repeatable deployment."
echo "Azure subscription : ${AZURE_SUBSCRIPTION_NAME} (${AZURE_SUBSCRIPTION_ID})"
if [ -n "$RESOURCE_GROUP" ]; then
  echo "Resource group     : ${RESOURCE_GROUP}"
fi
if [ -n "$AKS_CLUSTER_NAME" ]; then
  echo "AKS cluster        : ${AKS_CLUSTER_NAME}"
fi
echo "kubectl context    : ${KUBECTL_CONTEXT}"
echo "Radius workspace   : ${WORKSPACE_NAME}"
echo "Radius group       : ${GROUP_NAME}"
echo "Next command       : ./scripts/bootstrap.sh --resource-group ${RESOURCE_GROUP} --yes"

if [ "$DRY_RUN" = true ]; then
  log_info "Dry run complete. Re-run without --dry-run to execute the plan."
fi

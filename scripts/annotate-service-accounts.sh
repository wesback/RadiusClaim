#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/platform-common.sh"

# annotate-service-accounts.sh — Annotate Kubernetes Service Accounts for Workload Identity
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │  POST-BICEP WIRING — Run after workload-identity.bicep deployment   │
# │                                                                     │
# │  This script annotates Kubernetes service accounts with the Azure  │
# │  workload identity client ID so that pods can authenticate to      │
# │  Azure resources using federated credentials.                      │
# │                                                                     │
# │  Prerequisites (handled by bootstrap.sh + workload-identity.bicep): │
# │    ✓ AKS cluster has OIDC issuer + workload identity addon         │
# │    ✓ User-assigned managed identity created                        │
# │    ✓ Federated identity credentials configured                     │
# │    ✓ RBAC roles assigned on Azure resources (in recipes)           │
# │    ✓ Dapr Component CRDs created (by Radius recipes)               │
# │                                                                     │
# │  This script only handles:                                         │
# │    → Annotate Kubernetes service accounts with client ID           │
# │    → Verify Dapr components exist (read-only validation)           │
# └─────────────────────────────────────────────────────────────────────┘
#
# Usage:
#   ./scripts/annotate-service-accounts.sh [OPTIONS]
#
# Options:
#   --namespace <name>         Kubernetes namespace (required)
#   --client-id <id>           Azure workload identity client ID (required)
#   --verify-components        Verify Dapr components exist (optional)
#   --dry-run                  Show what would be done without applying
#   --help                     Show this help message

NAMESPACE=""
CLIENT_ID=""
VERIFY_COMPONENTS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --client-id)
      CLIENT_ID="$2"
      shift 2
      ;;
    --verify-components)
      VERIFY_COMPONENTS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      head -n 42 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage"
      exit 1
      ;;
  esac
done

if [[ -z "$NAMESPACE" || -z "$CLIENT_ID" ]]; then
  log_error "Missing required parameters: --namespace and --client-id are required"
  echo "Run with --help for usage"
  exit 2
fi

echo "=========================================="
echo "Annotating Service Accounts for Workload Identity"
echo "=========================================="
echo "Namespace:   $NAMESPACE"
echo "Client ID:   $CLIENT_ID"
echo "Dry Run:     $DRY_RUN"
echo ""

# Service accounts that need Azure workload identity access
SERVICE_ACCOUNTS=("expense-api" "workflow-engine" "notification-svc")

echo "→ Annotating service accounts with workload identity client ID..."
for SA_NAME in "${SERVICE_ACCOUNTS[@]}"; do
  echo "  → Service account: $SA_NAME"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "    [DRY RUN] Would create/annotate service account with azure.workload.identity/client-id=${CLIENT_ID}"
  else
    # Create service account if it doesn't exist (idempotent)
    kubectl create serviceaccount "$SA_NAME" -n "$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    # Annotate with workload identity client ID (overwrite if exists)
    kubectl annotate serviceaccount "$SA_NAME" \
      -n "$NAMESPACE" \
      azure.workload.identity/client-id="$CLIENT_ID" \
      --overwrite >/dev/null 2>&1
    
    echo "    ✓ Service account annotated"
  fi
done
echo ""

if [[ "$VERIFY_COMPONENTS" == "true" ]]; then
  echo "→ Verifying Dapr components exist..."
  
  COMPONENTS_JSON=$(kubectl get components -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
  EXPECTED_COMPONENTS=("statestore" "pubsub" "platform-secrets")
  
  for COMPONENT in "${EXPECTED_COMPONENTS[@]}"; do
    if echo "$COMPONENTS_JSON" | jq -e ".items[] | select(.metadata.name == \"$COMPONENT\")" >/dev/null 2>&1; then
      echo "  ✓ Component '$COMPONENT' exists"
    else
      log_warning "Component '$COMPONENT' not found in namespace '$NAMESPACE'"
      log_info "Components should be created by Radius recipes during deployment"
    fi
  done
  echo ""
fi

log_success "Service account annotation complete"
echo ""
echo "Next steps:"
echo "  1. Verify pods can authenticate: kubectl describe pod <pod-name> -n $NAMESPACE"
echo "  2. Check for workload identity annotation in service account projection"
echo "  3. Verify Dapr components are healthy: kubectl get components -n $NAMESPACE"

exit 0

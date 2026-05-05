#!/bin/bash
# Verify Dapr sidecars have all required components

set -euo pipefail

NAMESPACE=${1:-radiusclaim-azure}
APP_NAME="${APP_NAME:-radiusclaim}"
BOOTSTRAP_SCRIPT="scripts/bootstrap.sh"
APPLY_SCRIPT="scripts/apply-dapr-components-from-recipes.sh"
FAILURES=0

echo "🔍 Validating Dapr components are loaded for namespace: $NAMESPACE..."

check_literal() {
  local file="$1"
  local literal="$2"
  local message="$3"
  if ! grep -Fq "$literal" "$file"; then
    echo "    ❌ $message"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "  Checking static component projection contract..."

if [ ! -f "$APPLY_SCRIPT" ]; then
  echo "    ❌ Missing supported component apply script: $APPLY_SCRIPT"
  FAILURES=$((FAILURES + 1))
else
  check_literal "$APPLY_SCRIPT" "resourceMetadata.dapr" "Component apply flow should read resourceMetadata.dapr"
  check_literal "$APPLY_SCRIPT" "load_recipe_resource \"Applications.Dapr/secretStores\" \"platform-secrets\"" "Component apply flow should resolve platform-secrets"
  check_literal "$APPLY_SCRIPT" "STATESTORE_COMPONENT_NAME" "Component apply flow should derive statestore from live recipe outputs"
  check_literal "$APPLY_SCRIPT" "PUBSUB_COMPONENT_NAME" "Component apply flow should derive pubsub from live recipe outputs"
  check_literal "$APPLY_SCRIPT" "SECRETS_COMPONENT_NAME" "Component apply flow should derive platform-secrets from live recipe outputs"
fi

if [ ! -f "$BOOTSTRAP_SCRIPT" ]; then
  echo "    ❌ Missing bootstrap script: $BOOTSTRAP_SCRIPT"
  FAILURES=$((FAILURES + 1))
else
  check_literal "$BOOTSTRAP_SCRIPT" "apply-dapr-components-from-recipes.sh" "Bootstrap should use apply-dapr-components-from-recipes.sh"
fi

if [ $FAILURES -ne 0 ]; then
  echo "❌ FAIL: Static Dapr component contract drifted"
  exit 1
fi

resolve_live_namespace() {
  local requested="$1"
  local workload="$requested"

  if [[ "$requested" != *"-${APP_NAME}" ]]; then
    workload="${requested}-${APP_NAME}"
  fi

  if kubectl get namespace "$workload" >/dev/null 2>&1; then
    printf '%s\n' "$workload"
    return 0
  fi

  if kubectl get namespace "$requested" >/dev/null 2>&1; then
    printf '%s\n' "$requested"
    return 0
  fi

  return 1
}

# Check if kubectl/cluster is available
if ! command -v kubectl >/dev/null 2>&1; then
  echo "⏭️  SKIP: kubectl not found - skipping live cluster validation"
  echo "   Static contract checks passed; run this again on a deployed cluster for CRD verification"
  exit 2
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "⏭️  SKIP: Kubernetes cluster not reachable - skipping live cluster validation"
  echo "   Static contract checks passed; run this again with a configured cluster"
  exit 2
fi

if ! LIVE_NAMESPACE="$(resolve_live_namespace "$NAMESPACE")"; then
  echo "⏭️  SKIP: Neither '$NAMESPACE' nor its workload namespace is present"
  echo "   Deploy the app first, then re-run this check"
  exit 2
fi

echo "  Using live namespace: $LIVE_NAMESPACE"

# List of required Dapr components (based on RadiusClaim architecture)
REQUIRED_COMPONENTS=(
  "statestore"
  "pubsub"
  "platform-secrets"
)

echo "  Checking for required Dapr components..."

for component in "${REQUIRED_COMPONENTS[@]}"; do
  if kubectl get component "$component" -n "$LIVE_NAMESPACE" >/dev/null 2>&1; then
    echo "    ✅ Component found: $component"
  else
    echo "    ❌ Component missing: $component"
    FAILURES=$((FAILURES + 1))
  fi
done

component_type() {
  local component="$1"
  kubectl get component "$component" -n "$LIVE_NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null || true
}

component_metadata() {
  local component="$1"
  kubectl get component "$component" -n "$LIVE_NAMESPACE" -o jsonpath='{range .spec.metadata[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null || true
}

echo "  Verifying live component types and metadata..."

STATESTORE_TYPE="$(component_type statestore)"
if [ "$STATESTORE_TYPE" = "state.postgresql" ]; then
  echo "    ✅ statestore uses state.postgresql"
else
  echo "    ❌ statestore type drifted: '$STATESTORE_TYPE'"
  FAILURES=$((FAILURES + 1))
fi

PUBSUB_TYPE="$(component_type pubsub)"
if [ "$PUBSUB_TYPE" = "pubsub.azure.servicebus.topics" ]; then
  echo "    ✅ pubsub uses pubsub.azure.servicebus.topics"
else
  echo "    ❌ pubsub type drifted: '$PUBSUB_TYPE'"
  FAILURES=$((FAILURES + 1))
fi

SECRETS_TYPE="$(component_type platform-secrets)"
if [ "$SECRETS_TYPE" = "secretstores.azure.keyvault" ]; then
  echo "    ✅ platform-secrets uses secretstores.azure.keyvault"
else
  echo "    ❌ platform-secrets type drifted: '$SECRETS_TYPE'"
  FAILURES=$((FAILURES + 1))
fi

STATESTORE_METADATA="$(component_metadata statestore)"
if printf '%s\n' "$STATESTORE_METADATA" | grep -q '^actorStateStore=true$'; then
  echo "    ✅ statestore advertises actorStateStore=true"
else
  echo "    ❌ statestore missing actorStateStore=true metadata"
  FAILURES=$((FAILURES + 1))
fi
if printf '%s\n' "$STATESTORE_METADATA" | grep -q '^keyPrefix=none$'; then
  echo "    ✅ statestore advertises keyPrefix=none"
else
  echo "    ❌ statestore missing keyPrefix=none metadata"
  FAILURES=$((FAILURES + 1))
fi

PUBSUB_METADATA="$(component_metadata pubsub)"
if printf '%s\n' "$PUBSUB_METADATA" | grep -q '^namespaceName='; then
  echo "    ✅ pubsub advertises namespaceName metadata"
else
  echo "    ❌ pubsub missing namespaceName metadata"
  FAILURES=$((FAILURES + 1))
fi

SECRETS_METADATA="$(component_metadata platform-secrets)"
if printf '%s\n' "$SECRETS_METADATA" | grep -q '^vaultName='; then
  echo "    ✅ platform-secrets advertises vaultName metadata"
else
  echo "    ❌ platform-secrets missing vaultName metadata"
  FAILURES=$((FAILURES + 1))
fi

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: All required Dapr components are loaded with the current contract"
  exit 0
else
  echo "❌ FAIL: Found $FAILURES Dapr component contract issue(s)"
  echo "   Refresh components with scripts/apply-dapr-components-from-recipes.sh"
  exit 1
fi

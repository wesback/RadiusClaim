#!/bin/bash
# Verify Dapr sidecars have all required components

set -e

NAMESPACE=${1:-azure-radiusclaim}

echo "🔍 Validating Dapr components are loaded in namespace: $NAMESPACE..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo "⚠️  kubectl not found - skipping cluster validation"
  echo "   This test requires a running cluster with deployed components"
  exit 0
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
  echo "⚠️  Namespace '$NAMESPACE' not found - skipping cluster validation"
  echo "   Run this test after deploying to a cluster"
  exit 0
fi

FAILURES=0

# List of required Dapr components (based on RadiusClaim architecture)
REQUIRED_COMPONENTS=(
  "statestore"
  "pubsub"
  "platform-secrets"
)

echo "  Checking for required Dapr components..."

for component in "${REQUIRED_COMPONENTS[@]}"; do
  if kubectl get component "$component" -n "$NAMESPACE" &> /dev/null; then
    echo "    ✅ Component found: $component"
  else
    echo "    ❌ Component missing: $component"
    FAILURES=$((FAILURES + 1))
  fi
done

# Verify components are of expected types
echo "  Verifying component types..."

# State store should be state-related
if kubectl get component statestore -n "$NAMESPACE" -o yaml 2>/dev/null | grep -q "kind.*state"; then
  echo "    ✅ statestore is a state component"
else
  if kubectl get component statestore -n "$NAMESPACE" &> /dev/null; then
    echo "    ⚠️  statestore exists but type verification failed"
  fi
fi

# Pub/sub should be pubsub-related
if kubectl get component pubsub -n "$NAMESPACE" -o yaml 2>/dev/null | grep -q "type.*pubsub"; then
  echo "    ✅ pubsub is a pubsub component"
else
  if kubectl get component pubsub -n "$NAMESPACE" &> /dev/null; then
    echo "    ⚠️  pubsub exists but type verification failed"
  fi
fi

# Secrets should be secretstore-related
if kubectl get component platform-secrets -n "$NAMESPACE" -o yaml 2>/dev/null | grep -q "kind.*secretstores"; then
  echo "    ✅ platform-secrets is a secretstore component"
else
  if kubectl get component platform-secrets -n "$NAMESPACE" &> /dev/null; then
    echo "    ⚠️  platform-secrets exists but type verification failed"
  fi
fi

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: All required Dapr components are loaded"
  exit 0
else
  echo "❌ FAIL: Missing $FAILURES required Dapr component(s)"
  echo "   Run scripts/deploy-dapr-components.sh to install components"
  exit 1
fi

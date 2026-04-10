#!/bin/bash

echo "═══════════════════════════════════════════════════════════════"
echo "Dapr Component & State Store Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

NAMESPACE="radiusclaim-azure-radiusclaim"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        FAILED=$((FAILED + 1))
    fi
}

# 1. Check Dapr Components
echo "1. Dapr Components"
echo "────────────────────────────────────────────────────────────────"

kubectl get component -n $NAMESPACE statestore
check_status "statestore component CRD exists"

kubectl get component -n $NAMESPACE pubsub
check_status "pubsub component CRD exists"

# 2. Check Component Status
echo ""
echo "2. Component Details"
echo "────────────────────────────────────────────────────────────────"

echo ""
echo "Statestore Component:"
kubectl get component -n $NAMESPACE statestore -o yaml 2>/dev/null | grep -A 10 "metadata:\|spec:" || echo "(component details unavailable)"

echo ""
echo "Pubsub Component:"
kubectl get component -n $NAMESPACE pubsub -o yaml 2>/dev/null | grep -A 10 "metadata:\|spec:" || echo "(component details unavailable)"

# 3. Test state operations via Dapr
echo ""
echo "3. State Store Test (via Dapr sidecar)"
echo "────────────────────────────────────────────────────────────────"

EXPENSE_API_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name 2>/dev/null | head -1 | cut -d'/' -f2)

if [ -z "$EXPENSE_API_POD" ]; then
    echo -e "${RED}✗${NC} Could not find expense-api pod"
    exit 1
fi

echo "Using pod: $EXPENSE_API_POD"
echo ""

# Test state.set()
echo "Test: Set state value (expense-counter)"
TEST_STATE_SET=$(cat <<EOF
{
  "key": "expense-counter",
  "value": {
    "count": 42,
    "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  }
}
EOF
)

# Execute in pod
if kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
    curl -s -X POST http://localhost:3500/v1.0/state/statestore \
    -H "Content-Type: application/json" \
    -d "$TEST_STATE_SET" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Successfully set state value"
else
    echo -e "${RED}✗${NC} Failed to set state value"
    FAILED=$((FAILED + 1))
fi

# Test state.get()
echo ""
echo "Test: Get state value (expense-counter)"
if STATE_RESPONSE=$(kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
    curl -s http://localhost:3500/v1.0/state/statestore/expense-counter 2>/dev/null); then
    if echo "$STATE_RESPONSE" | grep -q "count"; then
        echo -e "${GREEN}✓${NC} Successfully retrieved state value"
        echo "  Response: $STATE_RESPONSE"
    else
        echo -e "${RED}✗${NC} State value not found or invalid"
        echo "  Response: $STATE_RESPONSE"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} Failed to get state value"
    FAILED=$((FAILED + 1))
fi

# 4. Test pub/sub
echo ""
echo "4. Pub/Sub Test"
echo "────────────────────────────────────────────────────────────────"

WORKFLOW_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=workflow-engine -o name 2>/dev/null | head -1 | cut -d'/' -f2)

if [ -z "$WORKFLOW_POD" ]; then
    echo -e "${YELLOW}⚠${NC} workflow-engine pod not found, skipping pub/sub subscriber test"
else
    echo "Using workflow pod: $WORKFLOW_POD"
    
    echo ""
    echo "Test: Publish message to pubsub"
    PUBSUB_MESSAGE=$(cat <<EOF
{
  "pubsubName": "pubsub",
  "topic": "expense.created",
  "data": {
    "expenseId": "test-$(date +%s)",
    "amount": 99.99
  }
}
EOF
)
    
    if kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
        curl -s -X POST http://localhost:3500/v1.0/publish/pubsub/expense.created \
        -H "Content-Type: application/json" \
        -d '{"expenseId":"test","amount":99.99}' > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Successfully published message"
    else
        echo -e "${RED}✗${NC} Failed to publish message"
        FAILED=$((FAILED + 1))
    fi
fi

# 5. Check Dapr Sidecar Health
echo ""
echo "5. Dapr Sidecar Health (expense-api)"
echo "────────────────────────────────────────────────────────────────"

if SIDECAR_HEALTH=$(kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
    curl -s http://localhost:3500/v1.0/healthz 2>/dev/null); then
    if [ -n "$SIDECAR_HEALTH" ]; then
        echo -e "${GREEN}✓${NC} Dapr sidecar is healthy"
        echo "  Response: $SIDECAR_HEALTH"
    else
        echo -e "${RED}✗${NC} Dapr sidecar health check returned empty"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} Could not reach Dapr sidecar on localhost:3500"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All Dapr component tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}$FAILED test(s) failed ✗${NC}"
    echo ""
    echo "Diagnostic commands:"
    echo "  kubectl logs $EXPENSE_API_POD -n $NAMESPACE -c daprd"
    echo "  kubectl logs $EXPENSE_API_POD -n $NAMESPACE"
    echo "  kubectl describe component statestore -n $NAMESPACE"
    echo "  kubectl describe component pubsub -n $NAMESPACE"
    exit 1
fi

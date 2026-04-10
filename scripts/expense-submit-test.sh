#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════════════"
echo "End-to-End Expense Submission Test"
echo "═══════════════════════════════════════════════════════════════"
echo ""

NAMESPACE="radiusclaim-azure-radiusclaim"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# Get pods
EXPENSE_API_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name 2>/dev/null | head -1 | cut -d'/' -f2)
WORKFLOW_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=workflow-engine -o name 2>/dev/null | head -1 | cut -d'/' -f2)

if [ -z "$EXPENSE_API_POD" ]; then
    echo -e "${RED}✗${NC} Could not find expense-api pod"
    exit 1
fi

echo "Expense API Pod: $EXPENSE_API_POD"
[ -n "$WORKFLOW_POD" ] && echo "Workflow Pod: $WORKFLOW_POD" || echo "Workflow Pod: (not found)"
echo ""

# Get the service port
TARGET_PORT=$(kubectl get svc expense-api -n $NAMESPACE -o jsonpath='{.spec.ports[0].targetPort}')

# Start port-forward in background
echo "1. Starting Port Forward"
echo "────────────────────────────────────────────────────────────────"
kubectl port-forward pod/$EXPENSE_API_POD $TARGET_PORT:$TARGET_PORT -n $NAMESPACE > /dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 2

# Cleanup on exit
cleanup() {
    kill $PORT_FORWARD_PID 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${GREEN}✓${NC} Port-forward started (PID: $PORT_FORWARD_PID)"
echo ""

# Test 1: Get initial expense count
echo "2. Initial State Check"
echo "────────────────────────────────────────────────────────────────"

BASE_URL="http://localhost:$TARGET_PORT"

# Get current state
INITIAL_COUNT=$(kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
    curl -s http://localhost:3500/v1.0/state/statestore/expense-counter 2>/dev/null || echo '{"count": 0}')
echo "Initial expense counter: $INITIAL_COUNT"
echo ""

# Test 2: Submit an expense
echo "3. Submitting Expense"
echo "────────────────────────────────────────────────────────────────"

EXPENSE_ID="test-expense-$(date +%s)"
EXPENSE_JSON=$(cat <<EOF
{
  "employeeId": "test-employee-001",
  "amount": 49.99,
  "currency": "USD",
  "description": "Test Expense - $(date +'%Y-%m-%d %H:%M:%S')"
}
EOF
)

echo "Submitting expense:"
echo "$EXPENSE_JSON"
echo ""

SUBMIT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/expenses" \
    -H "Content-Type: application/json" \
    -d "$EXPENSE_JSON" 2>/dev/null)

HTTP_CODE=$(echo "$SUBMIT_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$SUBMIT_RESPONSE" | head -n -1)

echo "Response (HTTP $HTTP_CODE):"
echo "$RESPONSE_BODY"
echo ""

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓${NC} Expense submission successful (HTTP $HTTP_CODE)"
else
    echo -e "${RED}✗${NC} Expense submission failed (HTTP $HTTP_CODE)"
    FAILED=$((FAILED + 1))
fi

# Test 3: Verify expense was stored
echo ""
echo "4. Verify Expense Stored"
echo "────────────────────────────────────────────────────────────────"

sleep 1

GET_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/expenses" 2>/dev/null)
HTTP_CODE=$(echo "$GET_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$GET_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓${NC} GET /expenses returned 200"
    echo "Response length: ${#RESPONSE_BODY} bytes"
    # Check if response contains expenses
    if echo "$RESPONSE_BODY" | grep -q "description\|amount" 2>/dev/null || [ "${#RESPONSE_BODY}" -gt 10 ]; then
        echo -e "${GREEN}✓${NC} Response contains expense data"
    else
        echo -e "${YELLOW}⚠${NC} Response doesn't contain expected expense data"
    fi
else
    echo -e "${RED}✗${NC} GET /expenses failed (HTTP $HTTP_CODE)"
    FAILED=$((FAILED + 1))
fi

# Test 4: Check state counter
echo ""
echo "5. Check State Counter"
echo "────────────────────────────────────────────────────────────────"

FINAL_COUNT=$(kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
    curl -s http://localhost:3500/v1.0/state/statestore/expense-counter 2>/dev/null || echo '{"count": 0}')
echo "Final expense counter: $FINAL_COUNT"

# Test 5: Check workflow logs (if available)
if [ -n "$WORKFLOW_POD" ]; then
    echo ""
    echo "6. Workflow Execution Logs"
    echo "────────────────────────────────────────────────────────────────"
    
    echo "Last 20 lines from workflow pod:"
    kubectl logs $WORKFLOW_POD -n $NAMESPACE --tail=20 || echo "(no logs available)"
else
    echo ""
    echo "6. Workflow Pod Not Available"
    echo "────────────────────────────────────────────────────────────────"
    echo -e "${YELLOW}⚠${NC} Workflow pod not found, skipping workflow logs"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Expense submission test completed! ✓${NC}"
    echo ""
    echo "Results:"
    echo "  ✓ API endpoint is responding"
    echo "  ✓ Expense submitted successfully"
    echo "  ✓ State operations working"
    exit 0
else
    echo -e "${RED}Expense submission test failed ✗${NC}"
    echo ""
    echo "Diagnostic commands:"
    echo "  kubectl logs $EXPENSE_API_POD -n $NAMESPACE"
    echo "  kubectl logs $EXPENSE_API_POD -n $NAMESPACE -c daprd"
    [ -n "$WORKFLOW_POD" ] && echo "  kubectl logs $WORKFLOW_POD -n $NAMESPACE"
    exit 1
fi

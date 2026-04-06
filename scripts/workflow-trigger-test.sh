#!/bin/bash

echo "═══════════════════════════════════════════════════════════════"
echo "Workflow Trigger & Event Test"
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

# Get pods
EXPENSE_API_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name 2>/dev/null | head -1 | cut -d'/' -f2)
WORKFLOW_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=workflow-engine -o name 2>/dev/null | head -1 | cut -d'/' -f2)

echo "1. Component Status"
echo "────────────────────────────────────────────────────────────────"

if [ -z "$EXPENSE_API_POD" ]; then
    echo -e "${RED}✗${NC} expense-api pod not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} Expense API Pod: $EXPENSE_API_POD"

if [ -z "$WORKFLOW_POD" ]; then
    echo -e "${RED}✗${NC} workflow-engine pod not found"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} Workflow Pod: $WORKFLOW_POD"
fi

# Check pub/sub component
echo ""
echo "2. Pub/Sub Component"
echo "────────────────────────────────────────────────────────────────"

kubectl get component -n $NAMESPACE pubsub > /dev/null 2>&1
check_status "pubsub component exists"

# Display pubsub config
echo ""
echo "Pubsub component details:"
kubectl get component -n $NAMESPACE pubsub -o yaml | head -30

# Test pub/sub publish
echo ""
echo "3. Publishing Test Event"
echo "────────────────────────────────────────────────────────────────"

EXPENSE_ID="workflow-test-$(date +%s)"
TEST_EVENT=$(cat <<EOF
{
  "expenseId": "$EXPENSE_ID",
  "description": "Workflow Test Expense",
  "amount": 75.50,
  "category": "Testing",
  "createdAt": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)

echo "Publishing event to 'expense.created' topic:"
echo "$TEST_EVENT"
echo ""

if PUBLISH_RESPONSE=$(kubectl exec -n $NAMESPACE $EXPENSE_API_POD -- \
    curl -s -w "\n%{http_code}" -X POST http://localhost:3500/v1.0/publish/pubsub/expense.created \
    -H "Content-Type: application/json" \
    -d "$TEST_EVENT" 2>/dev/null); then
    HTTP_CODE=$(echo "$PUBLISH_RESPONSE" | tail -1)
    BODY=$(echo "$PUBLISH_RESPONSE" | head -n -1)
    
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ] || [ -z "$BODY" ]; then
        echo -e "${GREEN}✓${NC} Successfully published event (HTTP $HTTP_CODE)"
    else
        echo -e "${RED}✗${NC} Publish failed (HTTP $HTTP_CODE)"
        echo "Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} Failed to execute publish command"
    FAILED=$((FAILED + 1))
fi

# Wait for workflow to process
echo ""
echo "4. Waiting for Workflow Processing"
echo "────────────────────────────────────────────────────────────────"
echo "Waiting 5 seconds for workflow to process event..."
sleep 5

# Check workflow logs
if [ -n "$WORKFLOW_POD" ]; then
    echo ""
    echo "5. Workflow Pod Logs (last 30 lines)"
    echo "────────────────────────────────────────────────────────────────"
    
    if kubectl logs $WORKFLOW_POD -n $NAMESPACE --tail=30 2>/dev/null; then
        check_status "Retrieved workflow logs"
    else
        echo -e "${YELLOW}⚠${NC} Could not retrieve workflow logs"
    fi
    
    # Check for subscription indication
    echo ""
    echo "6. Subscription Status"
    echo "────────────────────────────────────────────────────────────────"
    
    if kubectl logs $WORKFLOW_POD -n $NAMESPACE 2>/dev/null | grep -i "subscribe\|topic\|pubsub" > /dev/null; then
        echo -e "${GREEN}✓${NC} Workflow logs contain pub/sub subscription references"
    else
        echo -e "${YELLOW}⚠${NC} Workflow logs don't show pub/sub subscription"
    fi
fi

# Check Dapr sidecar logs for workflow component
echo ""
echo "7. Dapr Workflow Component Status"
echo "────────────────────────────────────────────────────────────────"

# List all components
echo "Deployed components:"
kubectl get component -n $NAMESPACE

# Check for workflow component
if kubectl get component -n $NAMESPACE -o name | grep -q workflow; then
    echo -e "${GREEN}✓${NC} Workflow component is deployed"
else
    echo -e "${YELLOW}⚠${NC} No workflow component found"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Workflow test completed! ✓${NC}"
else
    echo -e "${RED}$FAILED test(s) failed ✗${NC}"
fi

echo ""
echo "Additional diagnostic commands:"
echo "  # Workflow engine logs:"
echo "  kubectl logs $WORKFLOW_POD -n $NAMESPACE -f"
echo ""
echo "  # Dapr logs from workflow pod:"
echo "  kubectl logs $WORKFLOW_POD -n $NAMESPACE -c daprd -f"
echo ""
echo "  # Check dapr runtime state:"
echo "  kubectl exec $WORKFLOW_POD -n $NAMESPACE -- curl http://localhost:3500/v1.0/healthz"

exit $FAILED

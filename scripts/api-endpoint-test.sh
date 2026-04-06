#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════════════"
echo "Expense API Endpoint Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

NAMESPACE="radiusclaim-azure-radiusclaim"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# Get expense-api service info
echo "1. Service Information"
echo "────────────────────────────────────────────────────────────────"

EXPENSE_API_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name 2>/dev/null | head -1 | cut -d'/' -f2)
if [ -z "$EXPENSE_API_POD" ]; then
    echo -e "${RED}✗${NC} Could not find expense-api pod"
    exit 1
fi
echo -e "${GREEN}✓${NC} Found expense-api pod: $EXPENSE_API_POD"

# Get the service port
SERVICE_PORT=$(kubectl get svc expense-api -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}')
TARGET_PORT=$(kubectl get svc expense-api -n $NAMESPACE -o jsonpath='{.spec.ports[0].targetPort}')
echo "Service port: $SERVICE_PORT → target port: $TARGET_PORT"

# Validate port was found
if [ -z "$TARGET_PORT" ]; then
    echo -e "${RED}✗${NC} Could not determine target port from service"
    exit 1
fi

# Start port-forward in background
echo ""
echo "2. Starting Port Forward (localhost:$TARGET_PORT → $TARGET_PORT)"
echo "────────────────────────────────────────────────────────────────"
kubectl port-forward pod/$EXPENSE_API_POD $TARGET_PORT:$TARGET_PORT -n $NAMESPACE > /dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 2

# Cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up port-forward (PID: $PORT_FORWARD_PID)"
    kill $PORT_FORWARD_PID 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${GREEN}✓${NC} Port-forward started (PID: $PORT_FORWARD_PID)"
echo "  Command: kubectl port-forward pod/$EXPENSE_API_POD $TARGET_PORT:$TARGET_PORT -n $NAMESPACE"

# Test API endpoints
BASE_URL="http://localhost:$TARGET_PORT"

echo ""
echo "3. Testing Endpoints"
echo "────────────────────────────────────────────────────────────────"

# Test /health
echo ""
echo "Test: GET /health"
if RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/health" 2>/dev/null); then
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo -e "${GREEN}✓${NC} /health returned $HTTP_CODE"
        [ -n "$BODY" ] && echo "  Response: $BODY" || echo "  (empty body)"
    else
        echo -e "${RED}✗${NC} /health returned $HTTP_CODE"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} /health request failed"
    FAILED=$((FAILED + 1))
fi

# Test GET /expenses
echo ""
echo "Test: GET /expenses"
if RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/expenses" 2>/dev/null); then
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓${NC} /expenses returned $HTTP_CODE"
        echo "  Response: ${BODY:0:200}..."
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo -e "${YELLOW}⚠${NC} /expenses returned $HTTP_CODE (auth required, expected)"
    else
        echo -e "${RED}✗${NC} /expenses returned $HTTP_CODE"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} /expenses request failed"
    FAILED=$((FAILED + 1))
fi

# Test POST /expenses
echo ""
echo "Test: POST /expenses"
EXPENSE_JSON='{"description":"Test expense","amount":10.00,"category":"Test"}'
if RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/expenses" \
    -H "Content-Type: application/json" \
    -d "$EXPENSE_JSON" 2>/dev/null); then
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓${NC} /expenses POST returned $HTTP_CODE"
        echo "  Response: ${BODY:0:200}..."
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo -e "${YELLOW}⚠${NC} /expenses POST returned $HTTP_CODE (auth may be required)"
        echo "  Response: $BODY"
    else
        echo -e "${RED}✗${NC} /expenses POST returned $HTTP_CODE"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} /expenses POST request failed"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All endpoint tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}$FAILED test(s) failed ✗${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Check API logs: kubectl logs $EXPENSE_API_POD -n $NAMESPACE"
    echo "  2. Check Dapr sidecar: kubectl logs $EXPENSE_API_POD -n $NAMESPACE -c daprd"
    echo "  3. Describe pod: kubectl describe pod $EXPENSE_API_POD -n $NAMESPACE"
    exit 1
fi

#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════════════"
echo "RadiusClaim Deployment Health Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED=0

check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        FAILED=$((FAILED + 1))
    fi
}

# 1. Check Kubernetes cluster
echo "1. Kubernetes Cluster Status"
echo "────────────────────────────────────────────────────────────────"
kubectl cluster-info > /dev/null 2>&1
check_status "Kubernetes cluster is accessible"

# 2. Check namespaces
echo ""
echo "2. Namespaces"
echo "────────────────────────────────────────────────────────────────"
kubectl get ns | grep -q "radiusclaim-azure-radiusclaim"
check_status "radiusclaim-azure-radiusclaim namespace exists"

NAMESPACE="radiusclaim-azure-radiusclaim"

# 3. Check Dapr
echo ""
echo "3. Dapr Installation"
echo "────────────────────────────────────────────────────────────────"
kubectl get deployment -n dapr-system dapr-operator > /dev/null 2>&1
check_status "Dapr operator is deployed"

kubectl get svc -n dapr-system dapr-api > /dev/null 2>&1
check_status "Dapr API service exists"

# 4. Check Expense API
echo ""
echo "4. Expense API Service"
echo "────────────────────────────────────────────────────────────────"
kubectl get svc expense-api -n $NAMESPACE > /dev/null 2>&1
check_status "expense-api service exists"

EXPENSE_API_READY=$(kubectl get svc expense-api -n $NAMESPACE -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")
if [ -n "$EXPENSE_API_READY" ]; then
    echo -e "${GREEN}✓${NC} expense-api service port is configured (target: $EXPENSE_API_READY)"
else
    echo -e "${RED}✗${NC} expense-api service has no target port"
    FAILED=$((FAILED + 1))
fi

# 5. Check Expense API Pod
echo ""
echo "5. Expense API Pod"
echo "────────────────────────────────────────────────────────────────"
EXPENSE_API_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name 2>/dev/null | wc -l)
if [ "$EXPENSE_API_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} expense-api pod exists ($EXPENSE_API_PODS pod(s))"
else
    echo -e "${RED}✗${NC} expense-api pod not found"
    FAILED=$((FAILED + 1))
fi

# Get pod status
EXPENSE_API_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name 2>/dev/null | head -1 | cut -d'/' -f2)
if [ -n "$EXPENSE_API_POD" ]; then
    POD_STATUS=$(kubectl get pod $EXPENSE_API_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓${NC} expense-api pod is running ($EXPENSE_API_POD)"
    else
        echo -e "${RED}✗${NC} expense-api pod status: $POD_STATUS"
        FAILED=$((FAILED + 1))
    fi
    
    # Check Dapr sidecar
    kubectl get pod $EXPENSE_API_POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | grep -q daprd
    check_status "Dapr sidecar is injected in expense-api pod"
else
    echo -e "${RED}✗${NC} Could not identify expense-api pod"
    FAILED=$((FAILED + 1))
fi

# 6. Check Workflow Pod
echo ""
echo "6. Workflow Engine Pod"
echo "────────────────────────────────────────────────────────────────"
WORKFLOW_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=workflow-engine -o name 2>/dev/null | wc -l)
if [ "$WORKFLOW_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} workflow-engine pod exists ($WORKFLOW_PODS pod(s))"
else
    echo -e "${RED}✗${NC} workflow-engine pod not found"
    FAILED=$((FAILED + 1))
fi

WORKFLOW_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=workflow-engine -o name 2>/dev/null | head -1 | cut -d'/' -f2)
if [ -n "$WORKFLOW_POD" ]; then
    POD_STATUS=$(kubectl get pod $WORKFLOW_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓${NC} workflow-engine pod is running ($WORKFLOW_POD)"
    else
        echo -e "${RED}✗${NC} workflow-engine pod status: $POD_STATUS"
        FAILED=$((FAILED + 1))
    fi
fi

# 7. Check Dapr Components
echo ""
echo "7. Dapr Components"
echo "────────────────────────────────────────────────────────────────"
kubectl get component -n $NAMESPACE statestore > /dev/null 2>&1
check_status "statestore component exists"

kubectl get component -n $NAMESPACE pubsub > /dev/null 2>&1
check_status "pubsub component exists"

# 8. Check ConfigMaps and Secrets
echo ""
echo "8. Configuration"
echo "────────────────────────────────────────────────────────────────"
kubectl get configmap -n $NAMESPACE > /dev/null 2>&1
check_status "ConfigMaps are present"

kubectl get secret -n $NAMESPACE > /dev/null 2>&1
check_status "Secrets are present"

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}$FAILED check(s) failed ✗${NC}"
    echo ""
    echo "Run the following for more details:"
    echo "  kubectl describe pod expense-api -n $NAMESPACE"
    echo "  kubectl logs \$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name | head -1) -n $NAMESPACE"
    echo "  kubectl logs \$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=expense-api -o name | head -1) -n $NAMESPACE -c daprd"
    exit 1
fi

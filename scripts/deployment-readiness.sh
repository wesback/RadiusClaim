#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════════════"
echo "Complete Deployment Readiness Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

run_test_script() {
    local SCRIPT_NAME=$1
    local SCRIPT_PATH="$SCRIPTS_DIR/$SCRIPT_NAME"
    
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "\033[1;33m⚠\033[0m  Script not found: $SCRIPT_NAME"
        return 1
    fi
    
    echo ""
    echo "Running: $SCRIPT_NAME"
    echo "───────────────────────────────────────────────────────────────────"
    
    if bash "$SCRIPT_PATH"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        return 0
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    fi
}

# Run test scripts in order
echo "Test Sequence:"
echo "1. Health Check - Verify cluster and pod status"
run_test_script "health-check.sh"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "2. API Endpoint Test - Verify API is responsive"
run_test_script "api-endpoint-test.sh"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "3. Dapr Component Test - Verify state store and pub/sub"
run_test_script "dapr-component-test.sh"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "4. Expense Submit Test - End-to-end submission test"
run_test_script "expense-submit-test.sh"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "5. Workflow Trigger Test - Verify workflow event processing"
run_test_script "workflow-trigger-test.sh"

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "DEPLOYMENT READINESS SUMMARY"
echo "═══════════════════════════════════════════════════════════════"

if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "\033[0;32m✓ ALL TESTS PASSED\033[0m"
    echo ""
    echo "Deployment is ready for production use."
    exit 0
else
    echo -e "\033[0;31m✗ TESTS FAILED: $TOTAL_FAILED issue(s) detected\033[0m"
    echo ""
    echo "Review the logs above for detailed failure information."
    exit 1
fi

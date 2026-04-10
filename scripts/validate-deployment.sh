#!/usr/bin/env bash
#
# RadiusClaim - Deployment Validation Script
#
# Validates end-to-end expense flows against a deployed RadiusClaim instance.
# Proves both the auto-approve ($50) and manual-review ($150) paths with observable assertions.
#
# Usage:
#   ./scripts/validate-deployment.sh <expense-api-base-url>
#
# Example:
#   ./scripts/validate-deployment.sh https://expense-api.radiusclaim.your-ingress-ip.nip.io
#
# Optional environment variables:
#   VALIDATION_OUTPUT_PATH - write machine-readable validation details for CI follow-up checks
#
# Prerequisites:
#   - jq installed
#   - curl installed
#   - expense-api accessible at the provided URL
#   - workflow-engine and notification-svc deployed and running
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation failed or error occurred

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation state
FAILURES=0
CHECKS_PASSED=0
CHECKS_TOTAL=0

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

check() {
    local description="$1"
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    echo -n "  Check ${CHECKS_TOTAL}: ${description}... "
}

pass() {
    echo -e "${GREEN}PASS${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

fail() {
    local message="$1"
    echo -e "${RED}FAIL${NC}"
    log_error "    ${message}"
    FAILURES=$((FAILURES + 1))
}

write_validation_output() {
    local output_path="${VALIDATION_OUTPUT_PATH:-}"

    if [ -z "$output_path" ]; then
        return 0
    fi

    if ! mkdir -p "$(dirname "$output_path")"; then
        log_warning "Failed to create directory for validation output artifact: ${output_path}"
        return 0
    fi

    if jq -nc \
        --arg apiUrl "$API_URL" \
        --argjson checksTotal "$CHECKS_TOTAL" \
        --argjson checksPassed "$CHECKS_PASSED" \
        --argjson failures "$FAILURES" \
        --arg autoExpenseId "${small_expense_id:-}" \
        --arg autoCorrelationId "${small_correlation_id:-}" \
        --arg manualExpenseId "${large_expense_id:-}" \
        --arg manualCorrelationId "${large_correlation_id:-}" \
        --arg boundaryExpenseId "${boundary_expense_id:-}" \
        --arg boundaryCorrelationId "${boundary_correlation_id:-}" \
        '{
            apiUrl: $apiUrl,
            summary: {
                checksTotal: $checksTotal,
                checksPassed: $checksPassed,
                failures: $failures
            },
            autoApprove: {
                expenseId: $autoExpenseId,
                correlationId: $autoCorrelationId
            },
            manualReview: {
                expenseId: $manualExpenseId,
                correlationId: $manualCorrelationId
            },
            boundary: {
                expenseId: $boundaryExpenseId,
                correlationId: $boundaryCorrelationId
            }
        }' > "$output_path"; then
        log_info "Validation details written to ${output_path}"
    else
        log_warning "Failed to write validation output artifact: ${output_path}"
    fi
}

# Parse arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <expense-api-base-url>"
    echo ""
    echo "Example:"
    echo "  $0 https://expense-api.radiusclaim.your-ingress-ip.nip.io"
    exit 1
fi

API_URL="${1%/}"  # Remove trailing slash if present
small_expense_id=""
small_correlation_id=""
large_expense_id=""
large_correlation_id=""
boundary_expense_id=""
boundary_correlation_id=""

# Validate prerequisites
log_info "Validating prerequisites..."
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install jq first."
    exit 1
fi
if ! command -v curl &> /dev/null; then
    log_error "curl is not installed. Please install curl first."
    exit 1
fi
log_success "Prerequisites validated"

# Test helper functions
submit_expense() {
    local amount="$1"
    local description="$2"
    local employee_id="$3"

    curl --fail --silent --show-error \
        --request POST \
        --url "${API_URL}/expenses/" \
        --header 'Content-Type: application/json' \
        --data "$(jq -nc \
            --arg employeeId "$employee_id" \
            --arg description "$description" \
            --argjson amount "$amount" \
            '{
                employeeId: $employeeId,
                amount: $amount,
                currency: "USD",
                description: $description
            }')"
}

get_expense() {
    local expense_id="$1"
    curl --fail --silent --show-error "${API_URL}/expenses/${expense_id}"
}

wait_for_status() {
    local expense_id="$1"
    local expected_status="$2"
    local max_attempts="${3:-30}"
    local acceptable_follow_on_status="${4:-}"
    local acceptable_follow_on_status="${4:-}"

    for attempt in $(seq 1 "$max_attempts"); do
        sleep 2
        local response
        response=$(get_expense "$expense_id" 2>/dev/null || echo '{}')
        local current_status
        current_status=$(jq -r '.status // empty' <<<"$response")
        
        if [ "$current_status" = "$expected_status" ]; then
            return 0
        fi

        if [ -n "$acceptable_follow_on_status" ] && [ "$current_status" = "$acceptable_follow_on_status" ]; then
            return 0
        fi

        if [ -n "$acceptable_follow_on_status" ] && [ "$current_status" = "$acceptable_follow_on_status" ]; then
            return 0
        fi
        
        # Show progress every 5 attempts
        if [ $((attempt % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done

    return 1
}

# Phase 7 Validation: Health Check
echo ""
log_info "Phase 7 Validation: Health Check"
echo "=================================="

check "API endpoint is accessible"
if health_response=$(curl --fail --silent --show-error --max-time 10 "${API_URL}/healthz" 2>&1); then
    if jq -e '.status == "ok"' <<<"$health_response" >/dev/null 2>&1; then
        pass
    else
        fail "Health endpoint returned unexpected response: ${health_response}"
    fi
else
    fail "Failed to reach health endpoint: ${health_response}"
fi

# Phase 7 Validation: Auto-Approve Flow ($50)
echo ""
log_info "Phase 7 Validation: Auto-Approve Flow (\$50)"
echo "=============================================="

check "Submit \$50 expense (under \$100 threshold)"
if small_response=$(submit_expense 50 'Phase 7 validation - auto-approve' 'emp-phase7-auto' 2>&1); then
    small_expense_id=$(jq -r '.expenseId' <<<"$small_response" 2>/dev/null || echo "")
    small_correlation_id=$(jq -r '.correlationId' <<<"$small_response" 2>/dev/null || echo "")
    
    if [ -z "$small_expense_id" ] || [ "$small_expense_id" = "null" ]; then
        fail "Response missing expenseId: ${small_response}"
    else
        pass
        log_info "    ExpenseId: ${small_expense_id}"
        log_info "    CorrelationId: ${small_correlation_id}"
    fi
else
    fail "Failed to submit expense: ${small_response}"
fi

if [ -n "${small_expense_id:-}" ] && [ "$small_expense_id" != "null" ]; then
    check "Initial status is 'Submitted'"
    initial_status=$(jq -r '.status' <<<"$small_response")
    if [ "$initial_status" = "Submitted" ]; then
        pass
    else
        fail "Expected 'Submitted', got '${initial_status}'"
    fi

    check "Expense progresses to 'Approved' status"
    echo -n "    Waiting"
    if wait_for_status "$small_expense_id" "Approved" 30 "Reimbursed"; then
        echo ""
        pass
    else
        echo ""
        fail "Expense did not reach 'Approved' status within timeout"
    fi

    check "Expense progresses to 'Reimbursed' status"
    echo -n "    Waiting"
    if wait_for_status "$small_expense_id" "Reimbursed" 30; then
        echo ""
        pass
    else
        echo ""
        fail "Expense did not reach 'Reimbursed' status within timeout"
    fi

    check "Final expense record has correct amount"
    final_record=$(get_expense "$small_expense_id")
    final_amount=$(jq -r '.amount' <<<"$final_record")
    if [ "$final_amount" = "50" ]; then
        pass
    else
        fail "Expected amount 50, got ${final_amount}"
    fi
fi

# Phase 7 Validation: Manual-Review Flow ($150)
echo ""
log_info "Phase 7 Validation: Manual-Review Flow (\$150)"
echo "==============================================="

check "Submit \$150 expense (at/above \$100 threshold)"
if large_response=$(submit_expense 150 'Phase 7 validation - manual review' 'emp-phase7-manual' 2>&1); then
    large_expense_id=$(jq -r '.expenseId' <<<"$large_response" 2>/dev/null || echo "")
    large_correlation_id=$(jq -r '.correlationId' <<<"$large_response" 2>/dev/null || echo "")
    
    if [ -z "$large_expense_id" ] || [ "$large_expense_id" = "null" ]; then
        fail "Response missing expenseId: ${large_response}"
    else
        pass
        log_info "    ExpenseId: ${large_expense_id}"
        log_info "    CorrelationId: ${large_correlation_id}"
    fi
else
    fail "Failed to submit expense: ${large_response}"
fi

if [ -n "${large_expense_id:-}" ] && [ "$large_expense_id" != "null" ]; then
    check "Initial status is 'Submitted'"
    initial_status=$(jq -r '.status' <<<"$large_response")
    if [ "$initial_status" = "Submitted" ]; then
        pass
    else
        fail "Expected 'Submitted', got '${initial_status}'"
    fi

    check "Expense progresses to 'ManualReviewRequested' status"
    echo -n "    Waiting"
    if wait_for_status "$large_expense_id" "ManualReviewRequested" 30; then
        echo ""
        pass
    else
        echo ""
        fail "Expense did not reach 'ManualReviewRequested' status within timeout"
    fi

    check "Status remains 'ManualReviewRequested' (not auto-approved)"
    sleep 5  # Give it a bit more time to ensure it doesn't progress further
    current_status=$(jq -r '.status' <<<"$(get_expense "$large_expense_id")")
    if [ "$current_status" = "ManualReviewRequested" ]; then
        pass
    else
        fail "Expected 'ManualReviewRequested', got '${current_status}'"
    fi

    check "Final expense record has correct amount"
    final_record=$(get_expense "$large_expense_id")
    final_amount=$(jq -r '.amount' <<<"$final_record")
    if [ "$final_amount" = "150" ]; then
        pass
    else
        fail "Expected amount 150, got ${final_amount}"
    fi
fi

# Phase 7 Validation: Boundary Case ($100.00 exactly)
echo ""
log_info "Phase 7 Validation: Boundary Case (\$100.00)"
echo "============================================="

check "Submit \$100.00 expense (exactly at threshold)"
if boundary_response=$(submit_expense 100 'Phase 7 validation - boundary' 'emp-phase7-boundary' 2>&1); then
    boundary_expense_id=$(jq -r '.expenseId' <<<"$boundary_response" 2>/dev/null || echo "")
    boundary_correlation_id=$(jq -r '.correlationId' <<<"$boundary_response" 2>/dev/null || echo "")
    
    if [ -z "$boundary_expense_id" ] || [ "$boundary_expense_id" = "null" ]; then
        fail "Response missing expenseId: ${boundary_response}"
    else
        pass
        log_info "    ExpenseId: ${boundary_expense_id}"
    fi
else
    fail "Failed to submit expense: ${boundary_response}"
fi

if [ -n "${boundary_expense_id:-}" ] && [ "$boundary_expense_id" != "null" ]; then
    check "\$100.00 expense enters manual review (not auto-approved)"
    echo -n "    Waiting"
    if wait_for_status "$boundary_expense_id" "ManualReviewRequested" 30; then
        echo ""
        pass
        log_info "    ✓ Threshold decision correct: \$100.00 is NOT auto-approved"
    else
        echo ""
        current_status=$(jq -r '.status' <<<"$(get_expense "$boundary_expense_id")")
        if [ "$current_status" = "Approved" ]; then
            fail "Boundary violated: \$100.00 was auto-approved (should require manual review)"
        else
            fail "Expense reached unexpected status: ${current_status}"
        fi
    fi
fi

# Summary
echo ""
echo "=========================================="
log_info "Validation Summary"
echo "=========================================="
echo "  Total checks: ${CHECKS_TOTAL}"
echo "  Passed:       ${CHECKS_PASSED}"
echo "  Failed:       ${FAILURES}"
echo ""

write_validation_output

if [ $FAILURES -eq 0 ]; then
    log_success "All Phase 7 validations PASSED"
    log_info "Distributed behavior validated:"
    log_info "  ✓ State persistence working"
    log_info "  ✓ Workflow orchestration working"
    log_info "  ✓ Service invocation working"
    log_info "  ✓ Auto-approve threshold < \$100.00"
    log_info "  ✓ Manual review threshold >= \$100.00"
    log_info "  ✓ Boundary case \$100.00 handled correctly"
    echo ""
    log_info "RadiusClaim deployment is HEALTHY and DEMO-READY."
    exit 0
else
    log_error "Phase 7 validation FAILED with ${FAILURES} error(s)"
    log_warning "Review the failures above and check:"
    log_warning "  - All three services are deployed and healthy"
    log_warning "  - Dapr sidecars are running"
    log_warning "  - State store and pub/sub components are configured"
    log_warning "  - Service-to-service invocation is working"
    exit 1
fi

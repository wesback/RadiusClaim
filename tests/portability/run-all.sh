#!/bin/bash
# Master script to run all portability validation tests

set -uo pipefail

echo "=========================================="
echo "RadiusClaim Portability Validation Suite"
echo "=========================================="
echo ""

# Track overall results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Array of test scripts to run
TESTS=(
  "app-no-azure-hardcoding.sh"
  "recipes-are-complete.sh"
  "bootstrap-idempotency.sh"
  "region-agnostic.sh"
  "dapr-components-loaded.sh"
)

# Run each test
for test in "${TESTS[@]}"; do
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo ""
  echo "Running: $test"
  echo "------------------------------------------"
  
  if bash "$SCRIPT_DIR/$test"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    status=$?
    if [ "$status" -eq 2 ]; then
      SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    else
      FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  fi
  
  echo ""
done

# Summary
echo "=========================================="
echo "Portability Validation Summary"
echo "=========================================="
echo "Total Tests:  $TOTAL_TESTS"
echo "Passed:       $PASSED_TESTS ✅"
echo "Skipped:      $SKIPPED_TESTS ⏭️"
echo "Failed:       $FAILED_TESTS ❌"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
  if [ $SKIPPED_TESTS -eq 0 ]; then
    echo "🎉 All portability validations passed!"
  else
    echo "🎉 Static portability validations passed."
    echo "   Cluster-dependent checks skipped: $SKIPPED_TESTS"
  fi
  echo ""
  echo "Your codebase adheres to the portability paradigm:"
  echo "  • App code is cloud-agnostic (uses Dapr abstractions)"
  echo "  • Radius recipe contracts match current bootstrap/component flows"
  echo "  • Bootstrap stays re-runnable and contract-aware"
  echo "  • Deployment is region-agnostic"
  echo "  • Dapr component checks only skip when a live cluster is required"
  exit 0
else
  echo "⚠️  Some portability validations failed."
  echo ""
  echo "Review the output above to identify and fix issues."
  echo "Each test script can be run individually for detailed debugging:"
  echo "  bash tests/portability/<test-name>.sh"
  exit 1
fi

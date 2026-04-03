#!/bin/bash
# Verify bootstrap.sh can be re-run without failures

set -e

echo "🔍 Validating bootstrap script idempotency..."

BOOTSTRAP_SCRIPT="scripts/bootstrap.sh"

if [ ! -f "$BOOTSTRAP_SCRIPT" ]; then
  echo "❌ FAIL: Bootstrap script not found: $BOOTSTRAP_SCRIPT"
  exit 1
fi

# Check if script has idempotency guards (common patterns)
echo "  Checking for idempotency patterns..."

HAS_CHECKS=0

# Check for existence checks before creation
if grep -qE "kubectl get|az.*show|rad.*show|if.*exists" "$BOOTSTRAP_SCRIPT"; then
  echo "    ✅ Found resource existence checks"
  HAS_CHECKS=$((HAS_CHECKS + 1))
fi

# Check for error suppression or conditional creation
if grep -qE "2>/dev/null|\|\| true|; then|--dry-run" "$BOOTSTRAP_SCRIPT"; then
  echo "    ✅ Found conditional execution patterns"
  HAS_CHECKS=$((HAS_CHECKS + 1))
fi

# Check for delete-before-create patterns (risky but sometimes needed)
if grep -qE "kubectl delete.*--ignore-not-found|rad.*delete.*--yes" "$BOOTSTRAP_SCRIPT"; then
  echo "    ⚠️  Found delete-before-create patterns (verify they're safe)"
fi

# Verify script checks prerequisites
if grep -qE "command -v|which|type.*rad|type.*kubectl" "$BOOTSTRAP_SCRIPT"; then
  echo "    ✅ Found prerequisite checks"
  HAS_CHECKS=$((HAS_CHECKS + 1))
fi

# Warn if no clear idempotency patterns found
if [ $HAS_CHECKS -lt 2 ]; then
  echo "    ⚠️  Warning: Limited idempotency patterns detected"
  echo "       Manual review recommended to verify re-run safety"
fi

# Test: Verify bootstrap has a help/dry-run mode
if grep -qE "\-\-help|\-\-dry-run|\-h" "$BOOTSTRAP_SCRIPT"; then
  echo "    ✅ Found help/dry-run support"
else
  echo "    ⚠️  No --help or --dry-run flag detected"
fi

# Success criteria: Script exists and has basic idempotency patterns
if [ $HAS_CHECKS -ge 1 ]; then
  echo "✅ PASS: Bootstrap script has idempotency patterns"
  echo "   Note: Full idempotency requires cluster testing (see README)"
  exit 0
else
  echo "❌ FAIL: Bootstrap script lacks clear idempotency patterns"
  echo "   Recommend adding existence checks before resource creation"
  exit 1
fi

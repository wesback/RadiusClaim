#!/bin/bash
# Verify bootstrap.sh still follows the current re-runnable Radius/Dapr contract

set -euo pipefail

echo "🔍 Validating bootstrap script idempotency..."

BOOTSTRAP_SCRIPT="scripts/bootstrap.sh"
COMPONENT_APPLY_SCRIPT="scripts/apply-dapr-components-from-recipes.sh"
FAILURES=0

if [ ! -f "$BOOTSTRAP_SCRIPT" ]; then
  echo "❌ FAIL: Bootstrap script not found: $BOOTSTRAP_SCRIPT"
  exit 1
fi

if [ ! -f "$COMPONENT_APPLY_SCRIPT" ]; then
  echo "❌ FAIL: Missing supported component refresh flow: $COMPONENT_APPLY_SCRIPT"
  exit 1
fi

require_literal() {
  local file="$1"
  local literal="$2"
  local message="$3"
  if ! grep -Fq "$literal" "$file"; then
    echo "    ❌ $message"
    FAILURES=$((FAILURES + 1))
  fi
}

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

echo "  Checking current Dapr component refresh flow..."
require_literal "$BOOTSTRAP_SCRIPT" "apply-dapr-components-from-recipes.sh" "Bootstrap should refresh components via apply-dapr-components-from-recipes.sh"
require_literal "$BOOTSTRAP_SCRIPT" "verify_components_present" "Bootstrap should verify projected Dapr components after refresh"
require_literal "$BOOTSTRAP_SCRIPT" "contains([\"statestore\", \"pubsub\", \"platform-secrets\"])" "Bootstrap should require statestore, pubsub, and platform-secrets"

if grep -Fq 'deploy-dapr-components.sh' "$BOOTSTRAP_SCRIPT"; then
  echo "    ❌ Bootstrap still references deprecated deploy-dapr-components.sh"
  FAILURES=$((FAILURES + 1))
fi

echo "  Checking platform-secrets / Key Vault contract handling..."
require_literal "$BOOTSTRAP_SCRIPT" "resolve_secret_store_key_vault_contract()" "Bootstrap should resolve the platform-secrets contract from Radius"
require_literal "$BOOTSTRAP_SCRIPT" ".properties.status.resourceMetadata.keyVaultName" "Bootstrap should read keyVaultName from resourceMetadata"
require_literal "$BOOTSTRAP_SCRIPT" ".properties.status.values.vaultName" "Bootstrap should fall back to values.vaultName"
require_literal "$BOOTSTRAP_SCRIPT" ".properties.status.resourceMetadata.vaultUri" "Bootstrap should read vaultUri from resourceMetadata"
require_literal "$BOOTSTRAP_SCRIPT" "discover_existing_kvrc_vault_name()" "Bootstrap should retain kvrc fallback discovery for idempotent reuse"
require_literal "$BOOTSTRAP_SCRIPT" "platform-secrets maps to Key Vault" "Bootstrap should log the platform-secrets mapping it resolved"

# Success criteria: Script exists and has basic idempotency patterns
if [ $HAS_CHECKS -ge 1 ] && [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: Bootstrap script matches the current idempotent platform contract"
  echo "   Note: Full idempotency requires cluster testing (see README)"
  exit 0
else
  if [ $HAS_CHECKS -lt 1 ]; then
    echo "❌ FAIL: Bootstrap script lacks clear idempotency patterns"
    echo "   Recommend adding existence checks before resource creation"
  else
    echo "❌ FAIL: Bootstrap script drifted from the current portability contract"
  fi
  exit 1
fi

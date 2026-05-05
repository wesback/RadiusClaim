#!/bin/bash
# Verify Radius recipe contracts match the current bootstrap/component generation flow

set -euo pipefail

echo "🔍 Validating Radius recipes are self-contained..."

RECIPE_DIR="infra/radius/recipes/azure"
FAILURES=0

if [ ! -d "$RECIPE_DIR" ]; then
  echo "❌ FAIL: Recipe directory not found: $RECIPE_DIR"
  exit 1
fi

check_literal() {
  local file="$1"
  local literal="$2"
  local message="$3"
  if ! grep -Fq "$literal" "$file"; then
    echo "    ❌ $message"
    FAILURES=$((FAILURES + 1))
  fi
}

check_regex() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "    ❌ $message"
    FAILURES=$((FAILURES + 1))
  fi
}

check_recipe_contract() {
  local recipe="$1"
  local recipe_name
  recipe_name=$(basename "$recipe")

  echo "  Checking recipe: $recipe_name"

  check_regex "$recipe" "^param context object$" "Missing 'param context object'"
  check_regex "$recipe" "^param location string" "Missing parameterized 'location' input"
  check_regex "$recipe" "^output values object" "Missing 'output values object'"
  check_regex "$recipe" "^output resourceMetadata object" "Missing 'output resourceMetadata object'"
  check_literal "$recipe" "dapr: {" "Missing resourceMetadata.dapr contract"
  check_literal "$recipe" "componentName:" "Missing Dapr component name metadata"
  check_literal "$recipe" "componentType:" "Missing Dapr component type metadata"
  check_literal "$recipe" "componentVersion:" "Missing Dapr component version metadata"
  check_literal "$recipe" "metadata: {" "Missing Dapr metadata payload"

  if grep -Eq "^output[[:space:]]+resources[[:space:]]" "$recipe"; then
    echo "    ❌ Uses explicit 'output resources' despite current Radius auto-populated outputResources contract"
    FAILURES=$((FAILURES + 1))
  fi

  if grep -E "location:.*'(francecentral|eastus|westus|northeurope|westeurope)'" "$recipe" 2>/dev/null; then
    echo "    ❌ Hardcoded location found (should use the location parameter)"
    FAILURES=$((FAILURES + 1))
  fi
}

REQUIRED_RECIPES=("state-store.bicep" "pubsub.bicep" "secrets.bicep")
for required in "${REQUIRED_RECIPES[@]}"; do
  if [ ! -f "$RECIPE_DIR/$required" ]; then
    echo "  ❌ Required recipe missing: $required"
    FAILURES=$((FAILURES + 1))
  fi
done

for recipe in "$RECIPE_DIR"/*.bicep; do
  [ -f "$recipe" ] || continue
  check_recipe_contract "$recipe"
done

STATE_RECIPE="$RECIPE_DIR/state-store.bicep"
PUBSUB_RECIPE="$RECIPE_DIR/pubsub.bicep"
SECRETS_RECIPE="$RECIPE_DIR/secrets.bicep"

if [ -f "$STATE_RECIPE" ]; then
  echo "  Checking PostgreSQL state store contract..."
  check_literal "$STATE_RECIPE" "componentType: 'state.postgresql'" "State store should advertise state.postgresql"
  check_literal "$STATE_RECIPE" "connectionString:" "State store should surface a connection string"
  check_literal "$STATE_RECIPE" "useAzureAD: 'true'" "State store should advertise Azure AD auth"
  check_literal "$STATE_RECIPE" "actorStateStore: 'true'" "State store should enable actorStateStore"
  check_literal "$STATE_RECIPE" "keyPrefix: 'none'" "State store should pin keyPrefix to 'none'"
fi

if [ -f "$PUBSUB_RECIPE" ]; then
  echo "  Checking Service Bus pub/sub contract..."
  check_literal "$PUBSUB_RECIPE" "componentType: 'pubsub.azure.servicebus.topics'" "Pub/sub should advertise the Service Bus topics component"
  check_literal "$PUBSUB_RECIPE" "namespaceName:" "Pub/sub should surface namespaceName metadata"
  check_literal "$PUBSUB_RECIPE" "disableEntityManagement: 'false'" "Pub/sub should keep entity management enabled"
fi

if [ -f "$SECRETS_RECIPE" ]; then
  echo "  Checking Key Vault secret store contract..."
  check_literal "$SECRETS_RECIPE" "var daprComponentName = 'platform-secrets'" "Secret store should publish the platform-secrets component"
  check_literal "$SECRETS_RECIPE" "componentType: 'secretstores.azure.keyvault'" "Secret store should advertise Azure Key Vault"
  check_literal "$SECRETS_RECIPE" "vaultName:" "Secret store should surface vaultName metadata"
  check_literal "$SECRETS_RECIPE" "vaultUri:" "Secret store should surface vaultUri metadata"
  check_literal "$SECRETS_RECIPE" "keyVaultName:" "Secret store should include keyVaultName resource metadata"
  check_literal "$SECRETS_RECIPE" "keyVaultId:" "Secret store should include keyVaultId resource metadata"
  check_literal "$SECRETS_RECIPE" "resourceGroup:" "Secret store should include resourceGroup resource metadata"
fi

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: Recipes match the current Radius output contract"
  exit 0
else
  echo "❌ FAIL: Found $FAILURES issue(s) in recipe contracts"
  exit 1
fi

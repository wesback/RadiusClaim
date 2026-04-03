#!/bin/bash
# Verify recipes are self-contained and complete

set -e

echo "🔍 Validating Radius recipes are self-contained..."

RECIPE_DIR="infra/radius/recipes/azure"
FAILURES=0

if [ ! -d "$RECIPE_DIR" ]; then
  echo "❌ FAIL: Recipe directory not found: $RECIPE_DIR"
  exit 1
fi

# Check each .bicep recipe file
for recipe in "$RECIPE_DIR"/*.bicep; do
  if [ ! -f "$recipe" ]; then
    continue
  fi
  
  recipe_name=$(basename "$recipe")
  echo "  Checking recipe: $recipe_name"
  
  # Verify recipe has required parameters
  if ! grep -q "^param context object" "$recipe"; then
    echo "    ❌ Missing 'param context object' (required by Radius)"
    FAILURES=$((FAILURES + 1))
  fi
  
  # Verify recipe has outputs (recipes should expose connection info)
  if ! grep -q "^output" "$recipe"; then
    echo "    ⚠️  Warning: Recipe has no outputs (may not expose connection info)"
  fi
  
  # Verify recipe uses parameterized location, not hardcoded
  if grep -E "location:.*'(francecentral|eastus|westus)'" "$recipe" 2>/dev/null; then
    echo "    ❌ Hardcoded location found (should use context.runtime.kubernetes.environmentNamespace or parameter)"
    FAILURES=$((FAILURES + 1))
  fi
  
  # Note: .json files are compiled ARM templates, not metadata
  # The actual recipe registration happens via OCI publishing (see scripts/publish-radius-recipes.sh)
done

# Verify core recipes exist
REQUIRED_RECIPES=("state-store.bicep" "pubsub.bicep" "secrets.bicep")
for required in "${REQUIRED_RECIPES[@]}"; do
  if [ ! -f "$RECIPE_DIR/$required" ]; then
    echo "  ❌ Required recipe missing: $required"
    FAILURES=$((FAILURES + 1))
  fi
done

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: Recipes are self-contained and complete"
  exit 0
else
  echo "❌ FAIL: Found $FAILURES issue(s) in recipes"
  exit 1
fi

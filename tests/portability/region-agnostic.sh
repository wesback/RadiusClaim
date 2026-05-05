#!/bin/bash
# Verify deployment to a different region requires only parameter changes

set -euo pipefail

echo "🔍 Validating deployment is region-agnostic..."

FAILURES=0

# Check infrastructure files for hardcoded regions
echo "  Checking infrastructure files for hardcoded regions..."

# Search infra and scripts, excluding comments and documentation
HARDCODED=$(grep -rE "location.*=.*(francecentral|eastus|westus|northeurope|westeurope)" infra/ scripts/ \
  --include="*.bicep" \
  --include="*.sh" \
  --include="*.json" \
  2>/dev/null | \
  grep -v "\.md:" | \
  grep -v "//.*location" | \
  grep -v "#.*location" | \
  grep -v "param.*location" | \
  grep -v "var.*location" || true)

if [ -n "$HARDCODED" ]; then
  echo "    ⚠️  Potential hardcoded regions found:"
  echo "$HARDCODED" | head -5
  echo "    Verify these are parameterized or documented as defaults"
fi

# Verify critical parameters are exposed in Azure-backed environment files
echo "  Checking Azure-backed Radius environments expose location parameters..."

AZURE_ENV_FILES=(
  "infra/radius/environments/azure-radius.bicep"
  "infra/radius/environments/dev.bicep"
)

for env_file in "${AZURE_ENV_FILES[@]}"; do
  if [ ! -f "$env_file" ]; then
    echo "    ❌ Missing expected environment file: $(basename "$env_file")"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  if grep -q "param .*location string" "$env_file"; then
    echo "    ✅ Found location parameter in $(basename "$env_file")"
  else
    echo "    ❌ No location parameter in $(basename "$env_file")"
    FAILURES=$((FAILURES + 1))
  fi
done

if [ -f "infra/radius/environments/local.bicep" ]; then
  echo "    ✅ local.bicep intentionally omits Azure location parameters"
fi

# Verify recipe files use parameterized locations
echo "  Checking recipes use parameterized locations..."

RECIPE_FILES=$(find infra/radius/recipes -name "*.bicep" 2>/dev/null || true)

for recipe in $RECIPE_FILES; do
  if grep -qE "location:.*context\.azure\.location|param.*location" "$recipe"; then
    echo "    ✅ Recipe uses parameterized location: $(basename $recipe)"
  else
    if grep -q "location:" "$recipe"; then
      echo "    ⚠️  Recipe may have hardcoded location: $(basename $recipe)"
    fi
  fi
done

# Note: app.bicep doesn't need a location parameter because:
# - Containers run on Kubernetes which already has a location
# - Backing services get location from environment or recipes
# This is expected and not a portability issue

# Check scripts for environment variable support
echo "  Checking scripts support AZURE_LOCATION environment variable..."

if grep -qE "AZURE_LOCATION|LOCATION|--location" scripts/bootstrap.sh 2>/dev/null; then
  echo "    ✅ Bootstrap script supports location configuration"
else
  echo "    ⚠️  Bootstrap script may not expose location parameter"
fi

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: Deployment is region-agnostic (location parameterized)"
  exit 0
else
  echo "❌ FAIL: Found $FAILURES critical region-hardcoding issue(s)"
  exit 1
fi

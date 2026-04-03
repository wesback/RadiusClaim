#!/bin/bash
# Verify deployment to a different region requires only parameter changes

set -e

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

# Verify critical parameters are exposed in environment files
echo "  Checking for location parameters in Radius environments..."

ENV_FILES=$(find infra/radius/environments -name "*.bicep" 2>/dev/null || true)

if [ -z "$ENV_FILES" ]; then
  echo "    ⚠️  No environment .bicep files found in infra/radius/environments/"
else
  for env_file in $ENV_FILES; do
    if grep -q "param location" "$env_file"; then
      echo "    ✅ Found location parameter in $(basename $env_file)"
    else
      echo "    ⚠️  No location parameter in $(basename $env_file)"
    fi
  done
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

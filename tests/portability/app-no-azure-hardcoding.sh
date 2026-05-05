#!/bin/bash
# Fail if service code or the Radius app definition references non-portable Azure specifics

set -euo pipefail

echo "🔍 Validating app code contains no hardcoded Azure references..."

# Track failures
FAILURES=0
APP_DEF="infra/radius/app.bicep"

# Check for hardcoded Azure subscription/resource group references
if grep -r "subscription\|resource_group" src/ --include="*.cs" --include="*.csproj" 2>/dev/null | grep -v "Microsoft.Azure.Cosmos\|Microsoft.Extensions" | grep -v "//.*subscription\|<!--.*subscription"; then
  echo "❌ FAIL: App code contains hardcoded subscription/resource_group references"
  FAILURES=$((FAILURES + 1))
fi

# Check for hardcoded Azure region names
if grep -rE "francecentral|eastus|westus|northeurope|westeurope" src/ --include="*.cs" --include="*.csproj" 2>/dev/null | grep -v "//.*region\|<!--.*region"; then
  echo "❌ FAIL: App code contains hardcoded Azure region references"
  FAILURES=$((FAILURES + 1))
fi

# Verify all Azure SDK references go through Dapr abstraction (not direct Azure SDK usage in app code)
# Allow Azure.Identity for managed identity, but not direct storage/servicebus/etc clients
if grep -rE "using Azure\.(Storage|ServiceBus|Messaging|KeyVault|Data\.Tables);" src/ --include="*.cs" 2>/dev/null | grep -v "Dapr\|RadiusClaimDapr"; then
  echo "❌ FAIL: Direct Azure SDK usage detected (should use Dapr abstraction)"
  echo "   Found direct Azure SDK imports that bypass Dapr portability layer"
  FAILURES=$((FAILURES + 1))
fi

# Verify no hardcoded connection strings in code
if grep -rE "DefaultEndpointsProtocol=https|AccountKey=|SharedAccessKey=" src/ --include="*.cs" 2>/dev/null | grep -v "//.*connection\|<!--.*connection"; then
  echo "❌ FAIL: Hardcoded connection strings detected in app code"
  FAILURES=$((FAILURES + 1))
fi

# Verify the Radius app definition doesn't fall back to raw in-cluster service URLs
if [ ! -f "$APP_DEF" ]; then
  echo "❌ FAIL: Radius app definition not found: $APP_DEF"
  FAILURES=$((FAILURES + 1))
elif grep -nE "http://(expense-api|workflow-engine|notification-svc)([:/]|$)|\\.svc\\.cluster\\.local" "$APP_DEF" 2>/dev/null; then
  echo "❌ FAIL: Radius app definition contains raw service URLs"
  echo "   Use Dapr app IDs/service invocation and Radius connections instead"
  FAILURES=$((FAILURES + 1))
fi

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: App portability contract is intact"
  exit 0
else
  echo "❌ FAIL: Found $FAILURES portability violation(s) in app portability contract"
  exit 1
fi

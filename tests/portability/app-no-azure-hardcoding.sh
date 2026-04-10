#!/bin/bash
# Fail if any service code references hardcoded Azure resource names, subscriptions, regions

set -e

echo "🔍 Validating app code contains no hardcoded Azure references..."

# Track failures
FAILURES=0

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

if [ $FAILURES -eq 0 ]; then
  echo "✅ PASS: App code is portable (no hardcoded Azure references)"
  exit 0
else
  echo "❌ FAIL: Found $FAILURES portability violation(s) in app code"
  exit 1
fi

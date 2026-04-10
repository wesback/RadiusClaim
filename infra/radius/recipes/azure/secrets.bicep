// RadiusClaim — Radius recipe: Azure Key Vault secret store
//
// Recipe name: 'kvrc' (abbreviation: Key Vault recipe)
// Dapr component type: 'secretstores.azure.keyvault/v2'
//
// ────────────────────────────────────────────────────────────────────────────
// WHAT IT DOES
// ────────────────────────────────────────────────────────────────────────────
// 1. Provisions an Azure Key Vault (naming: kvrc{randomSuffix})
// 2. Enforces Entra RBAC authorization (no legacy access policies)
// 3. Emits metadata for the Dapr secret store component (vault name, vault URI)
//
// ────────────────────────────────────────────────────────────────────────────
// HOW IT INTEGRATES WITH DAPR
// ────────────────────────────────────────────────────────────────────────────
// Workload flow:
//   1. app.bicep defines a 'platformSecrets' connection to this recipe
//   2. Radius deploys the recipe, creating the Key Vault
//   3. Radius creates a Dapr component (CRD) with:
//      - name: 'platform-secrets'
//      - type: 'secretstores.azure.keyvault/v2'
//      - metadata: { vaultName, vaultUri, ... }
//   4. Dapr sidecar in workload pods auto-discovers the component
//   5. App code calls Dapr Secret APIs (GetSecretAsync) to retrieve secrets
//   6. Dapr routes secret requests through the sidecar to the Key Vault
//
// ────────────────────────────────────────────────────────────────────────────
// AUTHENTICATION & SECURITY
// ────────────────────────────────────────────────────────────────────────────
// - Authorization: Azure RBAC only (enableRbacAuthorization: true)
// - No legacy access policies (modern Azure security model)
// - Authentication: Microsoft Entra workload identity (Dapr sidecar → Key Vault)
// - Role: Key Vault Secrets User (assigned to Dapr managed identity)
// - Soft delete: Enabled (7-day retention for accidental deletions)
// - Purge protection: NOT enabled (can be enabled once, but cannot be disabled)
//
// Radius injects `context` automatically when the recipe runs.

@description('Radius-provided deployment context (injected by the platform).')
param context object

@description('Azure region for the Key Vault. Supplied by environment recipe parameters.')
param location string

@description('Azure AD tenant ID. Extracted from subscription context when not explicitly provided.')
param tenantId string = subscription().tenantId

@description('Optional random suffix for non-deterministic naming (dev/demo environments). If provided, replaces uniqueString generation.')
param randomNameSuffix string = ''

@description('Principal (object) ID of the Dapr workload identity for RBAC assignments.')
param daprPrincipalId string

@description('Client (application) ID of the Dapr workload identity for component auth metadata.')
param daprClientId string = ''

@description('Azure environment (cloud). Options: AzurePublicCloud, AzureUSGovernment, AzureChina. Defaults to AzurePublicCloud for sovereign cloud support.')
param azureEnvironment string = 'AzurePublicCloud'

@description('Azure subscription ID for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureSubscriptionId string

@description('Azure resource group name for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureResourceGroupName string

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id)
// Key Vault names: 3-24 chars, alphanumeric + hyphens
var vaultName = 'kvrc${nameSuffix}'

// Explicit Azure resource ID — bypasses Radius deployment engine UCP scope resolution
var keyVaultArmId = '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroupName}/providers/Microsoft.KeyVault/vaults/${vaultName}'

// ---------------------------------------------------------------------------
// Key Vault — RBAC authorization (no access policies)
// ---------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // enablePurgeProtection removed — once enabled on a vault, it cannot be disabled
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC — Key Vault Secrets Officer for Dapr workload identity
// ---------------------------------------------------------------------------
// Removed from recipe: Radius v0.56 bicep-de cannot authenticate nested ARM
// deployments created by cross-scope modules (scope: resourceGroup(sub, rg)).
// RBAC is assigned post-deploy by bootstrap.sh via `az role assignment create`.

// ---------------------------------------------------------------------------
// Dapr Component Metadata — secretstores.azure.keyvault
// ---------------------------------------------------------------------------
// Radius recipes provision Azure resources only; Kubernetes CRDs (Dapr components)
// are created by the bootstrap script using the metadata outputted below.
// This separation follows Radius architecture: recipes = Azure provisioning,
// bootstrap = Kubernetes configuration.

var daprComponentName = 'platform-secrets'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------

output values object = {
  vaultName: keyVault.name
  vaultUri: keyVault.properties.vaultUri
  componentName: daprComponentName
}

// Omit explicit `output resources` — Radius auto-populates from ARM deployment.

// ---------------------------------------------------------------------------
// Structured metadata for declarative resource discovery
// ---------------------------------------------------------------------------
// Consumed by bootstrap.sh and other platform automation to discover resources
// without querying Azure by name patterns. Eliminates coupling to naming conventions.

output resourceMetadata object = {
  keyVaultName: keyVault.name
  keyVaultId: keyVaultArmId
  vaultUri: keyVault.properties.vaultUri
  resourceGroup: azureResourceGroupName
  location: location
  // Dapr component metadata for bootstrap script
  dapr: {
    componentName: daprComponentName
    componentType: 'secretstores.azure.keyvault'
    componentVersion: 'v1'
    metadata: {
      vaultName: keyVault.name
      azureClientId: daprClientId
      azureEnvironment: azureEnvironment
    }
  }
}

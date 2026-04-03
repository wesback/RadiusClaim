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

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id)
// Key Vault names: 3-24 chars, alphanumeric + hyphens
var vaultName = 'kvrc${nameSuffix}'

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

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, daprPrincipalId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: daprPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Dapr Component CRD — secretstores.azure.keyvault
// ---------------------------------------------------------------------------
// NOTE: Dapr component is created separately (e.g., by deployment-dapr-components-workload-identity.sh)
// This recipe outputs metadata for the component; Radius does not manage the K8s resource itself.

var daprComponentName = 'platform-secrets'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------

output values object = {
  vaultName: keyVault.name
  vaultUri: keyVault.properties.vaultUri
  componentName: daprComponentName
}

output resources array = [
  keyVault.id
]

// ---------------------------------------------------------------------------
// Structured metadata for declarative resource discovery
// ---------------------------------------------------------------------------
// Consumed by bootstrap.sh and other platform automation to discover resources
// without querying Azure by name patterns. Eliminates coupling to naming conventions.

output resourceMetadata object = {
  keyVaultName: keyVault.name
  keyVaultId: keyVault.id
  vaultUri: keyVault.properties.vaultUri
  resourceGroup: split(keyVault.id, '/')[4]
  location: location
}

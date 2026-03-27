targetScope = 'resourceGroup'

@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Azure location for the backing Key Vault resource.')
param location string = resourceGroup().location

@description('Key Vault name for the Azure-backed Dapr secret store.')
param vaultName string = 'ce-${take(uniqueString(context.resource.id, 'keyvault'), 20)}'

@description('Tenant ID used by the Key Vault resource and Dapr secretstore metadata.')
param azureTenantId string = subscription().tenantId

@description('Microsoft Entra client ID used by the Dapr secretstore component. When set, workload identity auth is projected into the component metadata.')
param azureClientId string = ''

@description('Object ID of the Microsoft Entra principal that should receive Key Vault Secrets User access.')
param azurePrincipalId string = ''

@description('Principal type for the Microsoft Entra identity used by the Dapr secretstore component.')
param azurePrincipalType string = 'ServicePrincipal'

var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
    tenantId: azureTenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: 7
    accessPolicies: []
  }
}

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(azurePrincipalId)) {
  name: guid(keyVault.id, azurePrincipalId, 'keyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: azurePrincipalId
    principalType: azurePrincipalType
  }
}

var secretStoreMetadata = union(
  {
    vaultName: { value: keyVault.name }
    vaultUri: { value: keyVault.properties.vaultUri }
    azureEnvironment: { value: 'AZUREPUBLICCLOUD' }
    azureTenantId: { value: azureTenantId }
  },
  empty(azureClientId) ? {} : { azureClientId: { value: azureClientId } }
)

output result object = {
  values: {
    type: 'secretstores.azure.keyvault'
    version: 'v1'
    metadata: secretStoreMetadata
  }
}

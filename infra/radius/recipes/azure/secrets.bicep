targetScope = 'resourceGroup'

@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Azure location for the backing Key Vault resource.')
param location string = resourceGroup().location

@description('Key Vault name for the Azure-backed Dapr secret store.')
param vaultName string = 'ce-${take(uniqueString(context.resource.id, 'keyvault'), 20)}'

@description('Tenant ID used by the Key Vault resource.')
param tenantId string = subscription().tenantId

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: 7
    accessPolicies: []
  }
}

output result object = {
  resources: [
    keyVault.id
  ]
  values: {
    type: 'secretstores.azure.keyvault'
    version: 'v1'
    metadata: {
      vaultName: {
        value: keyVault.name
      }
      vaultUri: {
        value: keyVault.properties.vaultUri
      }
      azureEnvironment: {
        value: 'AZUREPUBLICCLOUD'
      }
      azureTenantId: {
        value: tenantId
      }
    }
  }
}

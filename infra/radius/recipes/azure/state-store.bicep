targetScope = 'resourceGroup'

@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Azure location for the backing state store resources.')
param location string = resourceGroup().location

@description('Storage account name for the Azure Blob-backed Dapr state store.')
param storageAccountName string = toLower('ce${take(uniqueString(context.resource.id, 'storage'), 20)}')

@description('Blob container name used by the Dapr state store component.')
param containerName string = 'expense-state'

@description('Storage SKU for the backing Azure Storage account.')
param storageSku string = 'Standard_LRS'

@description('Microsoft Entra tenant ID used by the Dapr statestore component.')
param azureTenantId string = subscription().tenantId

@description('Microsoft Entra client ID used by the Dapr statestore component.')
param azureClientId string = ''

@description('Object ID of the Microsoft Entra principal that should receive Blob data-plane access.')
param azurePrincipalId string = ''

@description('Principal type for the Microsoft Entra identity used by the Dapr statestore component.')
param azurePrincipalType string = 'ServicePrincipal'

var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(azurePrincipalId)) {
  name: guid(storageAccount.id, azurePrincipalId, 'storageblobdatacontributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: azurePrincipalId
    principalType: azurePrincipalType
  }
}

var stateStoreMetadata = union({
  accountName: {
    value: storageAccount.name
  }
  containerName: {
    value: containerName
  }
  azureTenantId: {
    value: azureTenantId
  }
  azureEnvironment: {
    value: 'AZUREPUBLICCLOUD'
  }
}, empty(azureClientId) ? {} : {
  azureClientId: {
    value: azureClientId
  }
})

output result object = {
  values: {
    type: 'state.azure.blobstorage'
    version: 'v2'
    metadata: stateStoreMetadata
  }
}

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

var storageAccountKeys = storageAccount.listKeys()

#disable-next-line outputs-should-not-contain-secrets
output result object = {
  values: {
    type: 'state.azure.blobstorage'
    version: 'v2'
    metadata: {
      accountName: {
        value: storageAccount.name
      }
      containerName: {
        value: containerName
      }
    }
  }
  secrets: {
    metadata: {
      accountKey: {
        value: storageAccountKeys.keys[0].value
      }
    }
  }
}

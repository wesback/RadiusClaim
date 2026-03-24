// Secondary Azure Container Apps fallback.
// Radius does not currently expose ACA as a supported compute kind, so this file stays
// limited to the Azure-specific bootstrap and direct ACA deployment path.
targetScope = 'resourceGroup'

@description('Logical label for the ACA fallback bootstrap slice.')
param environmentName string = 'azure'

@description('Azure region for the Container Apps environment and backing resources.')
param location string = resourceGroup().location

@description('Azure Container Apps managed environment name.')
param containerAppsEnvironmentName string = 'cae-cloudexpense-${environmentName}'

@description('User-assigned managed identity shared by the three Container Apps and Azure-backed Dapr components.')
param managedIdentityName string = 'id-cloudexpense-${environmentName}'

@description('Log Analytics workspace name for ACA logs.')
param logAnalyticsWorkspaceName string = 'log-cloudexpense-${environmentName}'

@description('Azure Container Registry name used for the service images.')
param acrName string = toLower('ce${take(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName, 'acr'), 20)}')

@description('Storage account backing the statestore Dapr component.')
param storageAccountName string = toLower('ce${take(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName, 'state'), 20)}')

@description('Blob container name used by the Dapr statestore component.')
param stateContainerName string = 'expense-state'

@description('Service Bus namespace backing the pubsub Dapr component.')
param serviceBusNamespaceName string = 'sb-${take(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName, 'pubsub'), 20)}'

@description('Topic used by the workflow -> notification flow.')
param notificationTopicName string = 'expense-notifications'

@description('Subscription pre-created for notification-svc so the pub/sub path stays explicit when entity management is disabled.')
param notificationSubscriptionName string = 'notification-svc'

@description('Key Vault name used for the Dapr secret store plumbing.')
param keyVaultName string = 'kv-${take(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName, 'kv'), 20)}'

var serviceNames = [
  'expense-api'
  'workflow-engine'
  'notification-svc'
]

var stateStoreScopes = [
  'expense-api'
  'workflow-engine'
]

var pubsubScopes = [
  'workflow-engine'
  'notification-svc'
]

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var serviceBusDataOwnerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: 30
    features: {
      disableLocalAuth: false
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    sku: {
      name: 'PerGB2018'
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
  }
}

resource workloadIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
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

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stateContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource notificationTopic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: serviceBusNamespace
  name: notificationTopicName
  properties: {
    enableBatchedOperations: true
    maxSizeInMegabytes: 1024
  }
}

resource notificationSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: notificationTopic
  name: notificationSubscriptionName
  properties: {
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 90
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// The component names intentionally mirror infra/radius/app.bicep so src/ stays unchanged.
resource stateStoreComponent 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = {
  parent: containerAppsEnvironment
  name: 'statestore'
  properties: {
    componentType: 'state.azure.blobstorage'
    ignoreErrors: false
    initTimeout: '5s'
    metadata: [
      {
        name: 'accountName'
        value: storageAccount.name
      }
      {
        name: 'containerName'
        value: stateContainerName
      }
      {
        name: 'azureTenantId'
        value: subscription().tenantId
      }
      {
        name: 'azureClientId'
        value: workloadIdentity.properties.clientId
      }
      {
        name: 'azureEnvironment'
        value: 'AZUREPUBLICCLOUD'
      }
    ]
    scopes: stateStoreScopes
    version: 'v2'
  }
}

resource pubsubComponent 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = {
  parent: containerAppsEnvironment
  name: 'pubsub'
  properties: {
    componentType: 'pubsub.azure.servicebus.topics'
    ignoreErrors: false
    initTimeout: '5s'
    metadata: [
      {
        name: 'namespaceName'
        value: '${serviceBusNamespace.name}.servicebus.windows.net'
      }
      {
        name: 'azureTenantId'
        value: subscription().tenantId
      }
      {
        name: 'azureClientId'
        value: workloadIdentity.properties.clientId
      }
      {
        name: 'disableEntityManagement'
        value: 'true'
      }
    ]
    scopes: pubsubScopes
    version: 'v1'
  }
}

resource secretStoreComponent 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = {
  parent: containerAppsEnvironment
  name: 'platform-secrets'
  properties: {
    componentType: 'secretstores.azure.keyvault'
    ignoreErrors: false
    initTimeout: '5s'
    metadata: [
      {
        name: 'vaultName'
        value: keyVault.name
      }
      {
        name: 'azureTenantId'
        value: subscription().tenantId
      }
      {
        name: 'azureClientId'
        value: workloadIdentity.properties.clientId
      }
      {
        name: 'azureEnvironment'
        value: 'AZUREPUBLICCLOUD'
      }
    ]
    scopes: serviceNames
    version: 'v1'
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, workloadIdentity.id, 'acrpull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workloadIdentity.id, 'storageblobdatacontributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, workloadIdentity.id, 'servicebusdataowner')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: serviceBusDataOwnerRoleDefinitionId
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, workloadIdentity.id, 'keyvaultsecretsuser')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output containerRegistryId string = containerRegistry.id
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryRepositoryPrefix string = '${containerRegistry.properties.loginServer}/cloudexpense-lite'
output containerAppsEnvironmentId string = containerAppsEnvironment.id
output containerAppsEnvironmentResourceName string = containerAppsEnvironment.name
output workloadIdentityResourceId string = workloadIdentity.id
output workloadIdentityClientId string = workloadIdentity.properties.clientId
output storageAccountId string = storageAccount.id
output storageAccountResourceName string = storageAccount.name
output stateContainerResourceName string = stateContainer.name
output serviceBusNamespaceId string = serviceBusNamespace.id
output serviceBusNamespaceResourceName string = serviceBusNamespace.name
output notificationTopicResourceName string = notificationTopic.name
output keyVaultId string = keyVault.id
output keyVaultResourceName string = keyVault.name
output deploymentContract object = {
  deploymentMode: 'aca-fallback'
  environmentName: environmentName
  externalIngressApp: 'expense-api'
  services: serviceNames
  daprComponents: {
    stateStore: stateStoreComponent.name
    pubsub: pubsubComponent.name
    secretStore: secretStoreComponent.name
  }
  azureBacking: {
    storageAccount: storageAccount.name
    blobContainer: stateContainer.name
    serviceBusNamespace: serviceBusNamespace.name
    topic: notificationTopic.name
    keyVault: keyVault.name
  }
  validationGoal: 'aca-fallback-e2e'
}

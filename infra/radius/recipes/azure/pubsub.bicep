targetScope = 'resourceGroup'

@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Azure location for the backing Service Bus resources.')
param location string = resourceGroup().location

@description('Service Bus namespace name for the Azure-backed Dapr pub/sub component.')
param namespaceName string = 'radiusclaim-${take(uniqueString(context.resource.id, 'servicebus'), 18)}'

@description('Topic used by the RadiusClaim notification flow.')
param topicName string = 'expense-notifications'

@description('Subscription pre-created for the RadiusClaim notification subscriber when entity management stays disabled.')
param subscriptionName string = 'notification-svc'

@description('Service Bus SKU used for the demo namespace.')
@allowed([
  'Standard'
])
param skuName string = 'Standard'

@description('Microsoft Entra tenant ID used by the Dapr pubsub component.')
param azureTenantId string = subscription().tenantId

@description('Microsoft Entra client ID used by the Dapr pubsub component.')
param azureClientId string = ''

@description('Object ID of the Microsoft Entra principal that should receive Service Bus data-plane access.')
param azurePrincipalId string = ''

@description('Principal type for the Microsoft Entra identity used by the Dapr pubsub component.')
param azurePrincipalType string = 'ServicePrincipal'

var serviceBusDataOwnerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  sku: {
    name: skuName
    tier: skuName
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource topic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: namespace
  name: topicName
  properties: {
    enableBatchedOperations: true
    maxSizeInMegabytes: 1024
  }
}

resource topicSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: topic
  name: subscriptionName
  properties: {
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
}

resource serviceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(azurePrincipalId)) {
  name: guid(namespace.id, azurePrincipalId, 'servicebusDataOwner')
  scope: namespace
  properties: {
    roleDefinitionId: serviceBusDataOwnerRoleDefinitionId
    principalId: azurePrincipalId
    principalType: azurePrincipalType
  }
}

var pubsubMetadata = union({
  namespaceName: {
    value: '${namespace.name}.servicebus.windows.net'
  }
  disableEntityManagement: {
    value: 'true'
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
    type: 'pubsub.azure.servicebus.topics'
    version: 'v1'
    metadata: pubsubMetadata
  }
}

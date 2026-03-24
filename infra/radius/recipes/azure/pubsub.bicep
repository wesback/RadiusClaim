targetScope = 'resourceGroup'

@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Azure location for the backing Service Bus resources.')
param location string = resourceGroup().location

@description('Service Bus namespace name for the Azure-backed Dapr pub/sub component.')
param namespaceName string = 'radiusclaim-${take(uniqueString(context.resource.id, 'servicebus'), 18)}'

@description('Topic used by the RadiusClaim notification flow.')
param topicName string = 'expense-notifications'

@description('Service Bus SKU used for the demo namespace.')
@allowed([
  'Standard'
])
param skuName string = 'Standard'

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

resource authRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2024-01-01' existing = {
  parent: namespace
  name: 'RootManageSharedAccessKey'
}

var authRuleKeys = authRule.listKeys()

#disable-next-line outputs-should-not-contain-secrets
output result object = {
  resources: [
    namespace.id
    topic.id
    authRule.id
  ]
  values: {
    type: 'pubsub.azure.servicebus'
    version: 'v1'
    metadata: {
      namespaceName: {
        value: namespace.name
      }
      disableEntityManagement: {
        value: 'true'
      }
    }
  }
  secrets: {
    metadata: {
      connectionString: {
        value: authRuleKeys.primaryConnectionString
      }
    }
  }
}

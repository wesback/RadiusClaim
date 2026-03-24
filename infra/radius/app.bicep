extension radius

@description('The ID of your Radius environment. Automatically injected by the rad CLI.')
param environment string

@description('Logical Radius application name for the RadiusClaim deployment.')
param applicationName string = 'radiusclaim'

@description('Container registry/repository prefix for RadiusClaim service images.')
param containerRegistry string = 'ghcr.io/sovereignapp/radiusclaim'

@description('Shared image tag for the service images used by the current environment.')
param imageTag string = 'phase1'

@description('Deployment target label kept aligned to the active Radius environment.')
param deploymentTarget string = 'local'

@description('Logical Dapr backing definitions. Override these per environment to swap providers without renaming statestore, pubsub, or platform-secrets.')
param daprBackings object = {
  stateStore: {
    recipeName: 'azure-blob-state'
    type: 'state.azure.blobstorage'
    version: 'v1'
  }
  pubsub: {
    recipeName: 'azure-servicebus-pubsub'
    type: 'pubsub.azure.servicebus'
    version: 'v1'
  }
  secretStore: {
    recipeName: 'azure-keyvault-secrets'
    type: 'secretstores.azure.keyvault'
    version: 'v1'
  }
}

var radiusLocation = 'global'
var servicePort = 8080
var stateStoreAccountName = toLower('ce${take(uniqueString(applicationName, environment, 'statestore'), 20)}')
var stateStoreContainerName = 'expense-state'
var pubsubNamespaceName = 'cloudexpense-${take(uniqueString(applicationName, environment, 'pubsub'), 18)}'
var notificationTopicName = 'expense-notifications'
var secretVaultName = 'ce-${take(uniqueString(applicationName, environment, 'platform-secrets'), 20)}'
var stateStoreBacking = daprBackings.stateStore
var pubsubBacking = daprBackings.pubsub
var secretStoreBacking = daprBackings.secretStore

resource app 'Applications.Core/applications@2023-10-01-preview' = {
  name: applicationName
  location: radiusLocation
  properties: {
    environment: environment
  }
}

resource stateStore 'Applications.Dapr/stateStores@2023-10-01-preview' = {
  name: 'statestore'
  location: radiusLocation
  properties: {
    environment: environment
    application: app.id
    resourceProvisioning: 'recipe'
    recipe: {
      name: stateStoreBacking.recipeName
      parameters: {
        storageAccountName: stateStoreAccountName
        containerName: stateStoreContainerName
      }
    }
    type: stateStoreBacking.type
    version: stateStoreBacking.version
    metadata: {
      accountName: {
        value: stateStoreAccountName
      }
      containerName: {
        value: stateStoreContainerName
      }
    }
  }
}

resource pubsub 'Applications.Dapr/pubSubBrokers@2023-10-01-preview' = {
  name: 'pubsub'
  location: radiusLocation
  properties: {
    environment: environment
    application: app.id
    resourceProvisioning: 'recipe'
    recipe: {
      name: pubsubBacking.recipeName
      parameters: {
        namespaceName: pubsubNamespaceName
        topicName: notificationTopicName
      }
    }
    type: pubsubBacking.type
    version: pubsubBacking.version
    metadata: {
      namespaceName: {
        value: pubsubNamespaceName
      }
      disableEntityManagement: {
        value: 'true'
      }
    }
  }
}

resource platformSecretStore 'Applications.Dapr/secretStores@2023-10-01-preview' = {
  name: 'platform-secrets'
  location: radiusLocation
  properties: {
    environment: environment
    application: app.id
    resourceProvisioning: 'recipe'
    recipe: {
      name: secretStoreBacking.recipeName
      parameters: {
        vaultName: secretVaultName
      }
    }
    type: secretStoreBacking.type
    version: secretStoreBacking.version
    metadata: {
      vaultName: {
        value: secretVaultName
      }
      azureEnvironment: {
        value: 'AZUREPUBLICCLOUD'
      }
    }
  }
}

module expenseApi './modules/container-service.bicep' = {
  name: 'expense-api-service'
  params: {
    application: app.id
    name: 'expense-api'
    image: '${containerRegistry}/expense-api:${imageTag}'
    containerPort: servicePort
    env: {
      SERVICE_NAME: {
        value: 'expense-api'
      }
      PLATFORM_TARGET: {
        value: deploymentTarget
      }
    }
    connections: {
      workflow: {
        source: 'http://workflow-engine:${servicePort}'
      }
      state: {
        source: stateStore.id
      }
      secrets: {
        source: platformSecretStore.id
      }
    }
  }
}

module workflowEngine './modules/container-service.bicep' = {
  name: 'workflow-engine-service'
  params: {
    application: app.id
    name: 'workflow-engine'
    image: '${containerRegistry}/workflow-engine:${imageTag}'
    containerPort: servicePort
    env: {
      SERVICE_NAME: {
        value: 'workflow-engine'
      }
      PLATFORM_TARGET: {
        value: deploymentTarget
      }
    }
    connections: {
      state: {
        source: stateStore.id
      }
      pubsub: {
        source: pubsub.id
      }
      secrets: {
        source: platformSecretStore.id
      }
    }
  }
}

module notificationService './modules/container-service.bicep' = {
  name: 'notification-service'
  params: {
    application: app.id
    name: 'notification-svc'
    image: '${containerRegistry}/notification-svc:${imageTag}'
    containerPort: servicePort
    env: {
      SERVICE_NAME: {
        value: 'notification-svc'
      }
      PLATFORM_TARGET: {
        value: deploymentTarget
      }
    }
    connections: {
      pubsub: {
        source: pubsub.id
      }
      secrets: {
        source: platformSecretStore.id
      }
    }
  }
}

output deploymentModel object = {
  application: {
    name: app.name
    id: app.id
  }
  target: deploymentTarget
  services: [
    'expense-api'
    'workflow-engine'
    'notification-svc'
  ]
  daprComponents: {
    stateStore: stateStore.name
    pubsub: pubsub.name
    secretStore: platformSecretStore.name
  }
  daprBackings: {
    stateStore: stateStoreBacking
    pubsub: pubsubBacking
    secretStore: secretStoreBacking
  }
  azureBacking: {
    stateStoreAccountName: stateStoreAccountName
    pubsubNamespaceName: pubsubNamespaceName
    secretVaultName: secretVaultName
    notificationTopicName: notificationTopicName
  }
  recipeStatus: 'phase5-recipes-wired'
}

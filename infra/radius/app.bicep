extension radius

@description('The ID of your Radius environment. Automatically injected by the rad CLI.')
param environment string

@description('Logical Radius application name for the RadiusClaim deployment.')
param applicationName string = 'radiusclaim'

@description('Container registry/repository prefix for RadiusClaim service images. Override if you publish the service images somewhere other than the current repository GHCR namespace.')
param containerRegistry string = 'ghcr.io/wesback/radiusclaim'

@description('Published image tag for the service images used by the current environment. No default on purpose: pass the exact tag you pushed (for example the workflow SHA).')
param imageTag string

@description('Deployment target label kept aligned to the active Radius environment.')
param deploymentTarget string = 'local'

@description('DNS prefix Radius should use when generating the public expense-api gateway hostname.')
param publicGatewayPrefix string = 'expense'

@description('Optional fully qualified hostname for the public expense-api gateway. Leave empty to let Radius generate a hostname.')
param publicGatewayHostname string = ''

@description('Set to "true" when deploying to AKS with Azure Workload Identity enabled. Adds azure.workload.identity/use=true to all pod specs so the AKS webhook injects the projected service account token.')
param useWorkloadIdentity string = 'false'

@description('Name of the imagePullSecret in the workload namespace for pulling GHCR private images. Leave empty to skip imagePullSecrets injection.')
param ghcrImagePullRef string = ''

@description('''
Logical Dapr recipe selections. Override these per environment to swap providers without
renaming statestore, pubsub, or platform-secrets.

Each entry accepts an optional "parameters" object. When present, those parameters are
passed verbatim to the recipe (useful for local/in-cluster recipes that ignore Azure names).
When absent, computed Azure-specific defaults are passed (backwards-compatible).

Azure example (default):
  { stateStore: { recipeName: 'azure-blob-state' }, ... }

Local/in-cluster example:
  { stateStore: { recipeName: 'local-redis-state', parameters: {} }, ... }
''')
param daprBackings object = {
  stateStore: {
    recipeName: 'azure-blob-state'
  }
  pubsub: {
    recipeName: 'azure-servicebus-pubsub'
  }
  secretStore: {
    recipeName: 'azure-keyvault-secrets'
  }
}

var radiusLocation = 'global'
var servicePort = 8080
var stateStoreAccountName = toLower('ce${take(uniqueString(applicationName, environment, 'statestore'), 20)}')
var stateStoreContainerName = 'expense-state'
var pubsubNamespaceName = 'radiusclaim-${take(uniqueString(applicationName, environment, 'pubsub'), 18)}'
var notificationTopicName = 'expense-notifications'
var notificationSubscriptionName = 'notification-svc'
var secretVaultName = 'ce-${take(uniqueString(applicationName, environment, 'platform-secrets'), 20)}'
var stateStoreBacking = daprBackings.stateStore
var pubsubBacking = daprBackings.pubsub
var secretStoreBacking = daprBackings.secretStore

// Azure-computed defaults for each backing. Used when daprBackings.*.parameters is absent.
var defaultStateStoreParams = {
  storageAccountName: stateStoreAccountName
  containerName: stateStoreContainerName
}
var defaultPubsubParams = {
  namespaceName: pubsubNamespaceName
  topicName: notificationTopicName
  subscriptionName: notificationSubscriptionName
}
var defaultSecretStoreParams = {
  vaultName: secretVaultName
}

// When the backing includes explicit parameters (e.g., local recipes), use them verbatim.
// Otherwise fall back to the Azure-computed defaults to preserve backwards compatibility.
var stateStoreRecipeParams = stateStoreBacking.?parameters ?? defaultStateStoreParams
var pubsubRecipeParams = pubsubBacking.?parameters ?? defaultPubsubParams
var secretStoreRecipeParams = secretStoreBacking.?parameters ?? defaultSecretStoreParams
var workloadIdentityPodLabels = useWorkloadIdentity == 'true' ? { 'azure.workload.identity/use': 'true' } : {}
var pullSecrets = empty(ghcrImagePullRef) ? [] : [{ name: ghcrImagePullRef }]
var publicGatewayHost = empty(publicGatewayHostname)
  ? {
      prefix: publicGatewayPrefix
    }
  : {
      fullyQualifiedHostname: publicGatewayHostname
    }

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
      parameters: stateStoreRecipeParams
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
      parameters: pubsubRecipeParams
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
      parameters: secretStoreRecipeParams
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
    podLabels: workloadIdentityPodLabels
    imagePullSecrets: pullSecrets
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
    podLabels: workloadIdentityPodLabels
    imagePullSecrets: pullSecrets
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
    podLabels: workloadIdentityPodLabels
    imagePullSecrets: pullSecrets
  }
}

resource expenseApiGateway 'Applications.Core/gateways@2023-10-01-preview' = {
  name: 'expense-api-gateway'
  location: radiusLocation
  properties: {
    application: app.id
    hostname: publicGatewayHost
    routes: [
      {
        path: '/'
        destination: 'http://expense-api:${servicePort}'
      }
    ]
  }
  dependsOn: [
    expenseApi
  ]
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
    notificationSubscriptionName: notificationSubscriptionName
  }
  exposure: {
    publicService: 'expense-api'
    internalServices: [
      'workflow-engine'
      'notification-svc'
    ]
    gateway: {
      name: expenseApiGateway.name
      resourceType: 'Applications.Core/gateways'
      route: '/'
      hostnameMode: empty(publicGatewayHostname) ? 'radius-generated' : 'custom-fqdn'
      hostnamePrefix: empty(publicGatewayHostname) ? publicGatewayPrefix : null
      configuredHostname: empty(publicGatewayHostname) ? null : publicGatewayHostname
      note: 'rad deploy prints the resolved public endpoint after deployment.'
    }
  }
  recipeStatus: 'phase5-recipes-wired'
}

extension radius

@description('Radius dev environment name.')
param environmentName string = 'dev'

@description('Kubernetes namespace used for the local Radius development slice.')
param kubernetesNamespace string = 'radiusclaim-dev'

@description('Azure provider scope used by recipe-backed resources.')
param azureProviderScope string = resourceGroup().id

@description('Azure location for backing resources created by recipes.')
param location string = resourceGroup().location

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: environmentName
  properties: {
    compute: {
      kind: 'kubernetes'
      resourceId: 'self'
      namespace: kubernetesNamespace
    }
    providers: {
      azure: {
        scope: azureProviderScope
      }
    }
    recipes: {
      'Applications.Dapr/stateStores': {
        'azure-blob-state': {
          templateKind: 'bicep'
          templatePath: '../recipes/azure/state-store.bicep'
          parameters: {
            location: location
          }
        }
      }
      'Applications.Dapr/pubSubBrokers': {
        'azure-servicebus-pubsub': {
          templateKind: 'bicep'
          templatePath: '../recipes/azure/pubsub.bicep'
          parameters: {
            location: location
          }
        }
      }
      'Applications.Dapr/secretStores': {
        'azure-keyvault-secrets': {
          templateKind: 'bicep'
          templatePath: '../recipes/azure/secrets.bicep'
          parameters: {
            location: location
          }
        }
      }
    }
  }
}

output environmentModel object = {
  name: env.name
  computeTarget: 'local-kubernetes'
  namespace: kubernetesNamespace
  azureProviderScope: azureProviderScope
  recipes: {
    stateStore: 'azure-blob-state'
    pubsub: 'azure-servicebus-pubsub'
    secretStore: 'azure-keyvault-secrets'
  }
}

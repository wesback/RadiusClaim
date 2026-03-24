extension radius

@description('Radius environment name for the Azure-backed deployment slice.')
param environmentName string = 'azure'

@description('Kubernetes namespace used by the Radius-managed Azure slice.')
param kubernetesNamespace string = 'cloudexpense-lite-azure'

@description('Azure resource group scope used by the Radius Azure provider and recipes.')
param azureProviderScope string

@description('Azure location for backing resources created by recipes.')
param location string

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
  computeTarget: 'radius-kubernetes'
  namespace: kubernetesNamespace
  azureProviderScope: azureProviderScope
  recipes: {
    stateStore: 'azure-blob-state'
    pubsub: 'azure-servicebus-pubsub'
    secretStore: 'azure-keyvault-secrets'
  }
  portabilityNote: 'Radius remains the service wiring authority; Azure-specific work stays in recipes and provider scope.'
  acaGap: 'Radius does not currently expose Azure Container Apps as a compute kind, so ACA stays on the fallback path.'
}

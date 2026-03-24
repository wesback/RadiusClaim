extension radius

@description('Radius environment name for the Azure-backed Kubernetes deployment slice.')
param environmentName string = 'azure'

@description('Kubernetes namespace used by the Radius-managed Azure slice across AKS, Arc-enabled / Azure Local, or self-managed clusters.')
param kubernetesNamespace string = 'radiusclaim-azure'

@description('Azure resource group scope used by the Radius Azure provider and recipes.')
param azureProviderScope string

@description('Azure location for backing resources created by recipes.')
param location string

@description('OCI registry prefix that stores published Radius recipe artifacts for this repo.')
param recipeRegistry string = 'ghcr.io/wesback/radiusclaim/recipes'

@description('OCI tag used when resolving published Radius recipe artifacts.')
param recipeTag string = 'latest'

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
          templatePath: '${recipeRegistry}/state-store:${recipeTag}'
          parameters: {
            location: location
          }
        }
      }
      'Applications.Dapr/pubSubBrokers': {
        'azure-servicebus-pubsub': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/pubsub:${recipeTag}'
          parameters: {
            location: location
          }
        }
      }
      'Applications.Dapr/secretStores': {
        'azure-keyvault-secrets': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/secrets:${recipeTag}'
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
  recipeArtifacts: {
    registry: recipeRegistry
    tag: recipeTag
  }
  recipes: {
    stateStore: 'azure-blob-state'
    pubsub: 'azure-servicebus-pubsub'
    secretStore: 'azure-keyvault-secrets'
  }
  portabilityNote: 'Radius remains the service wiring authority across AKS, Arc-enabled Kubernetes / Azure Local, and self-managed Kubernetes clusters; Azure-specific work stays in recipes and provider scope.'
  kubernetesTargets: [
    'aks'
    'arc-enabled'
    'self-managed'
  ]
  azureSpecificityNote: 'Backing services in this environment still come from Azure Blob Storage, Service Bus, and Key Vault recipes.'
}

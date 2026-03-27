extension radius

@description('Radius environment name for the Azure-backed Kubernetes deployment slice.')
param environmentName string = 'azure'

@description('Kubernetes namespace used by the Radius-managed Azure slice across AKS, Arc-enabled / Azure Local, or self-managed clusters.')
param kubernetesNamespace string = 'radiusclaim-azure'

@description('Azure resource group scope used by the Radius Azure provider and recipes.')
param azureProviderScope string

@description('Azure location for backing resources created by recipes.')
param location string

@description('Microsoft Entra client ID Dapr components should use for Azure-backed services.')
param daprAzureClientId string = ''

@description('Microsoft Entra object ID that recipes should grant data-plane RBAC for Dapr runtime access.')
param daprAzurePrincipalId string = ''

@description('Microsoft Entra tenant ID Dapr components should use for Azure-backed services.')
param daprAzureTenantId string = ''

@description('Principal type for the Microsoft Entra identity used by Dapr runtime access.')
param daprAzurePrincipalType string = 'ServicePrincipal'

@description('OCI registry prefix that stores published Radius recipe artifacts for this repo.')
param recipeRegistry string = 'ghcr.io/wesback/radiusclaim/recipes'

@description('OCI tag used when resolving published Radius recipe artifacts.')
param recipeTag string = 'latest'

var identityParams = union(
  empty(daprAzureClientId) ? {} : { azureClientId: daprAzureClientId },
  empty(daprAzurePrincipalId) ? {} : { azurePrincipalId: daprAzurePrincipalId },
  empty(daprAzureTenantId) ? {} : { azureTenantId: daprAzureTenantId },
  (!empty(daprAzurePrincipalId) && !empty(daprAzurePrincipalType)) ? { azurePrincipalType: daprAzurePrincipalType } : {}
)

var stateStoreRecipeParameters = union({ location: location }, identityParams)
var pubsubRecipeParameters = union({ location: location }, identityParams)
var secretStoreRecipeParameters = union({ location: location }, identityParams)

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
          parameters: stateStoreRecipeParameters
        }
      }
      'Applications.Dapr/pubSubBrokers': {
        'azure-servicebus-pubsub': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/pubsub:${recipeTag}'
          parameters: pubsubRecipeParameters
        }
      }
      'Applications.Dapr/secretStores': {
        'azure-keyvault-secrets': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/secrets:${recipeTag}'
          parameters: secretStoreRecipeParameters
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
  stateStoreAuthModel: !empty(daprAzureClientId) ? 'microsoft-entra-rbac' : 'recipe-default'
  pubsubAuthModel: !empty(daprAzureClientId) ? 'microsoft-entra-rbac' : 'connection-string-fallback'
  secretStoreAuthModel: !empty(daprAzureClientId) ? 'microsoft-entra-rbac' : 'recipe-default'
  portabilityNote: 'Radius remains the service wiring authority across AKS, Arc-enabled Kubernetes / Azure Local, and self-managed Kubernetes clusters; Azure-specific work stays in recipes and provider scope.'
  kubernetesTargets: [
    'aks'
    'arc-enabled'
    'self-managed'
  ]
  azureSpecificityNote: 'Backing services in this environment still come from Azure Blob Storage, Service Bus, and Key Vault recipes; the statestore path is designed for Microsoft Entra/RBAC instead of shared keys.'
}

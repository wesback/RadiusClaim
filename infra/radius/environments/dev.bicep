// ---------------------------------------------------------------------------
// dev.bicep — Radius Environment: Development (Kubernetes + Azure Recipes)
// ---------------------------------------------------------------------------
// Development environment for local Kubernetes clusters (kind, k3d, Docker
// Desktop) that provisions REAL Azure backing services during inner-loop
// iteration. Developers get production-equivalent Dapr components without
// running a full cloud deployment pipeline.
//
// Structurally identical to azure-radius.bicep but namespaced separately so
// dev and production environments can coexist on the same cluster.
//
// Deploy:
//   rad deploy infra/radius/environments/dev.bicep \
//     -p azureSubscriptionId=<sub-id> \
//     -p azureResourceGroup=<rg-name>
// ---------------------------------------------------------------------------

extension radius

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Name of the Radius environment resource.')
param environmentName string = 'radiusclaim-dev'

@description('Kubernetes namespace where workloads deploy. Radius creates it if absent.')
param namespace string = 'radiusclaim-dev'

@description('OCI registry base path for Recipe Bicep modules.')
param recipeRegistry string = 'ghcr.io/wesback/radiusclaim/recipes'

@description('OCI tag for Recipe modules. Pin to a SHA for reproducible deploys.')
param recipeTag string = 'latest'

@description('Azure subscription ID for the Azure provider scope.')
param azureSubscriptionId string

@description('Azure resource group where Recipes provision backing resources.')
param azureResourceGroup string

@description('Azure region for resource provisioning.')
param location string = 'francecentral'

@description('Allow the Azure-services magic firewall rule on the PostgreSQL state store. Defaults to true for dev environments.')
param allowAzureServices bool = true

@description('Azure environment (cloud) for sovereign cloud DNS suffix resolution. Options: AzurePublicCloud, AzureUSGovernment, AzureChina.')
param azureEnvironment string = 'AzurePublicCloud'

@description('Enable a Private Endpoint for PostgreSQL state store. Defaults to false for dev environments.')
param usePrivateEndpoint bool = false

// ── Environment ─────────────────────────────────────────────────────────────

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: environmentName
  location: 'global'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: namespace
    }

    providers: {
      azure: {
        scope: '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroup}'
      }
    }

    recipes: {
      // Dapr State Store — provisions Azure PostgreSQL Flexible Server with Entra RBAC
      'Applications.Dapr/stateStores': {
        default: {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/state-store:${recipeTag}'
          parameters: {
            location: location
            allowAzureServices: allowAzureServices
            azureEnvironment: azureEnvironment
            usePrivateEndpoint: usePrivateEndpoint
          }
        }
      }

      // Dapr Pub/Sub Broker — provisions Azure Service Bus with Entra RBAC
      'Applications.Dapr/pubSubBrokers': {
        default: {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/pubsub:${recipeTag}'
          parameters: {
            location: location
          }
        }
      }

      // Dapr Secret Store — provisions Azure Key Vault with Entra RBAC
      'Applications.Dapr/secretStores': {
        default: {
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

// ── Outputs ──────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Radius environment.')
output environmentId string = env.id

@description('Kubernetes namespace targeted by this environment.')
output environmentNamespace string = namespace

@description('Workload namespace: where Dapr components are projected and workloads run.')
output workloadNamespace string = namespace

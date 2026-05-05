// ---------------------------------------------------------------------------
// local.bicep — Experimental placeholder for a local Radius environment
// ---------------------------------------------------------------------------
// This file is not part of the repo's currently supported deployment path.
// Local development uses the checked-in Dapr overlays under infra/dapr/local.
// Keep this file only as a placeholder for future local Radius recipe work.
//
// Deploying this environment still requires separately published local recipe
// artifacts; those source recipes are not shipped in this repository today.
// ---------------------------------------------------------------------------

extension radius

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Name of the Radius environment resource.')
param environmentName string = 'radiusclaim-local'

@description('Kubernetes namespace where workloads deploy. Radius creates it if absent.')
param namespace string = 'radiusclaim-local'

@description('OCI registry base path for local Recipe Bicep modules.')
param recipeRegistry string = 'ghcr.io/wesback/radiusclaim/recipes/local'

@description('OCI tag for Recipe modules.')
param recipeTag string = 'latest'

// ── Environment ─────────────────────────────────────────────────────────────

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: environmentName
  location: 'global'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: namespace
    }

    // No Azure provider — all recipes deploy in-cluster resources only.

    recipes: {
      // Dapr State Store — deploys Redis in Kubernetes
      'Applications.Dapr/stateStores': {
        default: {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/state-store:${recipeTag}'
        }
      }

      // Dapr Pub/Sub Broker — deploys RabbitMQ in Kubernetes
      'Applications.Dapr/pubSubBrokers': {
        default: {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/pubsub:${recipeTag}'
        }
      }

      // Dapr Secret Store — uses Kubernetes native secrets
      'Applications.Dapr/secretStores': {
        default: {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/secrets:${recipeTag}'
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

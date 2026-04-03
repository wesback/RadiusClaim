// ---------------------------------------------------------------------------
// local.bicep — Radius Environment: In-Cluster Recipes (No Azure)
// ---------------------------------------------------------------------------
// Targets a Kubernetes cluster with ALL backing services running in-cluster.
// No Azure provider — Recipes deploy Redis, RabbitMQ, and Kubernetes Secrets
// directly into the cluster. Zero cloud dependency.
//
// This environment proves the portability story: the same app.bicep that runs
// against Azure Service Bus and Key Vault also runs here against RabbitMQ and
// Kubernetes secrets — zero app code changes.
//
// Deploy:
//   rad deploy infra/radius/environments/local.bicep
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

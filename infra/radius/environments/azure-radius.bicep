// ---------------------------------------------------------------------------
// azure-radius.bicep — Radius Environment: Azure-backed Recipes
// ---------------------------------------------------------------------------
// Targets a Kubernetes cluster with Azure-provisioned backing services.
// All Dapr building blocks (state store, pub/sub, secrets) are wired through
// Radius Recipes that provision real Azure resources (Blob Storage, Service Bus,
// Key Vault) using Microsoft Entra workload identity for authentication.
//
// The application definition (app.bicep) does NOT change between environments.
// Only the Recipes and environment configuration differ — this is the core
// portability story.
//
// Deploy:
//   rad deploy infra/radius/environments/azure-radius.bicep \
//     -p azureProviderScope=/subscriptions/<sub-id>/resourceGroups/<rg-name> \
//     -p kubernetesNamespace=<namespace>
// ---------------------------------------------------------------------------

extension radius

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Name of the Radius environment resource.')
param environmentName string = 'radiusclaim-azure'

@description('Kubernetes namespace where workloads deploy. Radius creates it if absent.')
param kubernetesNamespace string = 'radiusclaim-azure'

// ── Workload Namespace Pattern ──────────────────────────────────────────────
// Dapr components are created in the Kubernetes namespace specified above.
// The Radius platform projects these as CRDs and injects them into the workload
// pods via Dapr sidecars.
//
// When workloads reference Dapr components (e.g., stateStore, pubSub), they use
// the component names defined in the recipes below (e.g., 'azure-postgres-statestore',
// 'azure-servicebus-pubsub'). These components are namespaced within
// kubernetesNamespace and are automatically wired to backing Azure resources.
//
// Example: environment 'radiusclaim-azure' + kubernetes namespace 'radiusclaim-azure'
//   → Dapr components created in 'radiusclaim-azure' namespace
//   → Workloads in the same namespace auto-discover and link to them

@description('OCI registry base path for Recipe Bicep modules.')
param recipeRegistry string = 'ghcr.io/wesback/radiusclaim/recipes'

@description('OCI tag for Recipe modules. Pin to a SHA for reproducible deploys.')
param recipeTag string = 'latest'

@description('Full Azure provider scope path (e.g. /subscriptions/{id}/resourceGroups/{rg}).')
param azureProviderScope string

@description('Azure subscription ID for recipe resource ID construction. Required to work around Radius deployment engine scope resolution.')
param azureSubscriptionId string = ''

@description('Azure resource group name for recipe resource ID construction. Required to work around Radius deployment engine scope resolution.')
param azureResourceGroupName string = ''

@description('Azure region for resource provisioning.')
param location string = 'francecentral'

// ── Dapr Workload Identity Parameters ──────────────────────────────────────
// Passed by bootstrap for Dapr component workload-identity authentication.

@description('Object (principal) ID of the managed identity / service principal for RBAC role assignments.')
param daprAzurePrincipalId string = ''

@description('Client (application) ID of the managed identity / service principal for Dapr component authentication.')
param daprAzureClientId string = ''

@description('Display name of the Dapr managed identity. Used as the Entra admin principalName and PostgreSQL connection user.')
param daprAzurePrincipalName string = ''

@description('Optional random suffix for recipe resource naming (dev/demo only). Format: 6-char timestamp hash. Empty for deterministic (prod) naming.')
param randomNameSuffix string = ''

@description('Azure tenant ID for Entra authentication in recipes that configure Microsoft Entra admin (e.g., PostgreSQL state store).')
param azureTenantId string = ''

// ── Environment ─────────────────────────────────────────────────────────────

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: environmentName
  location: 'global'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: kubernetesNamespace
    }

    providers: {
      azure: {
        scope: azureProviderScope
      }
    }

    recipes: {
      // Dapr State Store Recipe (staterc)
      // ────────────────────────────────────────────────────────────────────
      // Recipe: 'azure-postgres-statestore' → Dapr Component Type: 'state.postgresql/v2'
      //
      // What it does:
      //   - Provisions an Azure Database for PostgreSQL Flexible Server (naming: staterc{randomSuffix})
      //   - Disables password access, enforces Entra workload identity auth
      //   - Emits metadata for the Dapr state component (connection string, credentials)
      //
      // Why PostgreSQL?
      //   Dapr actors require transactional state stores. PostgreSQL supports full ACID transactions
      //   while Blob Storage does not. This enables workflow-engine to reliably persist actor state.
      //
      // Why this recipe name?
      //   'staterc' = 'state recipe' (consistent with other recipe abbreviations: pubsubrc, kvrc)
      //
      // Workload usage:
      //   Workloads define a 'stateStore' connection to this recipe (app.bicep).
      //   Dapr injects statestore as a component in the workload's sidecar.
      //   App code uses Dapr State APIs (e.g., SaveStateAsync) to persist data with transactional guarantees.
      // ────────────────────────────────────────────────────────────────────
      'Applications.Dapr/stateStores': {
        'azure-postgres-statestore': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/state-store:${recipeTag}'
          parameters: {
            location: location
            randomNameSuffix: randomNameSuffix
            daprPrincipalId: daprAzurePrincipalId
            daprPrincipalName: daprAzurePrincipalName
            daprClientId: daprAzureClientId
            azureSubscriptionId: azureSubscriptionId
            azureResourceGroupName: azureResourceGroupName
            azureTenantId: azureTenantId
          }
        }
      }

      // ────────────────────────────────────────────────────────────────────
      // Recipe: 'azure-servicebus-pubsub' → Dapr Component Type: 'pubsub.azure.servicebus/v1'
      //
      // What it does:
      //   - Provisions an Azure Service Bus namespace (naming: pubsubrc{randomSuffix})
      //   - Configures Entra workload identity auth; optionally emits SAS connection string
      //   - Emits metadata for the Dapr pub/sub component (namespace name, endpoint)
      //
      // Why this recipe name?
      //   'pubsubrc' = 'pub/sub recipe'
      //
      // Workload usage:
      //   Workloads define a 'pubsub' connection to this recipe (app.bicep).
      //   Dapr injects pubsub as a component in the workload's sidecar.
      //   App code uses Dapr Pub/Sub APIs (e.g., PublishEventAsync, SubscribeTopicAsync)
      //   for loosely coupled messaging between services.
      // ────────────────────────────────────────────────────────────────────
      'Applications.Dapr/pubSubBrokers': {
        'azure-servicebus-pubsub': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/pubsub:${recipeTag}'
          parameters: {
            location: location
            randomNameSuffix: randomNameSuffix
            daprPrincipalId: daprAzurePrincipalId
            daprClientId: daprAzureClientId
            azureSubscriptionId: azureSubscriptionId
            azureResourceGroupName: azureResourceGroupName
          }
        }
      }

      // Dapr Secret Store Recipe (kvrc)
      // ────────────────────────────────────────────────────────────────────
      // Recipe: 'azure-keyvault-secrets' → Dapr Component Type: 'secretstores.azure.keyvault/v2'
      //
      // What it does:
      //   - Provisions an Azure Key Vault (naming: kvrc{randomSuffix})
      //   - Enforces Entra RBAC authorization (no access policies)
      //   - Emits metadata for the Dapr secret store component (vault name, vault URI)
      //
      // Why this recipe name?
      //   'kvrc' = 'Key Vault recipe'
      //
      // Workload usage:
      //   Workloads define a 'platformSecrets' connection to this recipe (app.bicep).
      //   Dapr injects platform-secrets as a component in the workload's sidecar.
      //   App code uses Dapr Secret APIs (e.g., GetSecretAsync) to retrieve
      //   credentials, tokens, and sensitive configuration at runtime.
      // ────────────────────────────────────────────────────────────────────
      'Applications.Dapr/secretStores': {
        'azure-keyvault-secrets': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/secrets:${recipeTag}'
          parameters: {
            location: location
            randomNameSuffix: randomNameSuffix
            daprPrincipalId: daprAzurePrincipalId
            daprClientId: daprAzureClientId
            azureSubscriptionId: azureSubscriptionId
            azureResourceGroupName: azureResourceGroupName
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
output environmentNamespace string = kubernetesNamespace

@description('Workload namespace: where Dapr components are projected and workloads run.')
output workloadNamespace string = kubernetesNamespace

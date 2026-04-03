// RadiusClaim — Radius recipe: Azure Blob Storage state store
//
// Recipe name: 'staterc' (abbreviation: state recipe)
// Dapr component type: 'state.azure.blobstorage/v2'
//
// ────────────────────────────────────────────────────────────────────────────
// WHAT IT DOES
// ────────────────────────────────────────────────────────────────────────────
// 1. Provisions an Azure Storage Account (naming: staterc{randomSuffix})
// 2. Creates a blob container for expense state and workflow checkpoints
// 3. Disables shared-key access, enforces Entra workload identity authentication
// 4. Emits metadata for the Dapr state component (account name, container name)
//
// ────────────────────────────────────────────────────────────────────────────
// HOW IT INTEGRATES WITH DAPR
// ────────────────────────────────────────────────────────────────────────────
// Workload flow:
//   1. app.bicep defines a 'statestore' connection to this recipe
//   2. Radius deploys the recipe, creating the storage account
//   3. Radius creates a Dapr component (CRD) with:
//      - name: 'statestore'
//      - type: 'state.azure.blobstorage/v2'
//      - metadata: { accountName, containerName, ... }
//   4. Dapr sidecar in workload pods auto-discovers the component
//   5. App code calls Dapr State APIs (SaveStateAsync, GetStateAsync, etc.)
//   6. Dapr routes state calls through the sidecar to the Blob Storage account
//
// ────────────────────────────────────────────────────────────────────────────
// AUTHENTICATION & SECURITY
// ────────────────────────────────────────────────────────────────────────────
// - Shared-key access is explicitly DISABLED (Azure Policy compliance)
// - Authentication: Microsoft Entra workload identity (Dapr sidecar → Blob Storage)
// - Role: Storage Blob Data Contributor (assigned to Dapr managed identity)
// - Connection: Non-public, enforced HTTPS TLS1.2+
// - Public access to blobs: Disabled (private containers)
//
// Radius injects `context` automatically when the recipe runs.

@description('Radius-provided deployment context (injected by the platform).')
param context object

@description('Azure region for the storage account. Supplied by environment recipe parameters.')
param location string

@description('Name of the blob container that holds Dapr state.')
param containerName string = 'expense-state'

@description('Optional random suffix for non-deterministic naming (dev/demo environments). If provided, replaces uniqueString generation.')
param randomNameSuffix string = ''

@description('Principal (object) ID of the Dapr workload identity for RBAC assignments.')
param daprPrincipalId string

@description('Client (application) ID of the Dapr workload identity for component metadata.')
param daprClientId string

@description('Azure AD tenant ID for workload identity authentication.')
param daprTenantId string

@description('Kubernetes namespace where Dapr components will be deployed.')
param kubernetesNamespace string

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id)
var accountName = 'staterc${nameSuffix}'

// ---------------------------------------------------------------------------
// Storage Account — shared-key access disabled (Entra auth only)
// ---------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// ---------------------------------------------------------------------------
// Blob Service + Container
// ---------------------------------------------------------------------------

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// ---------------------------------------------------------------------------
// RBAC — Storage Blob Data Contributor for Dapr workload identity
// ---------------------------------------------------------------------------

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, daprPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: daprPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Dapr Component CRD — state.azure.blobstorage
// ---------------------------------------------------------------------------
// NOTE: Dapr component is created separately (e.g., by deployment-dapr-components-workload-identity.sh)
// This recipe outputs metadata for the component; Radius does not manage the K8s resource itself.

var daprComponentName = 'statestore'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------
// Radius expects `values` (flat key-value map surfaced to the Dapr component)
// and `resources` (Azure resource IDs for lifecycle tracking).

output values object = {
  accountName: storageAccount.name
  containerName: containerName
  actorStateStore: 'true'
  componentName: daprComponentName
}

output resources array = [
  storageAccount.id
]

// ---------------------------------------------------------------------------
// Structured metadata for declarative resource discovery
// ---------------------------------------------------------------------------
// Consumed by bootstrap.sh and other platform automation to discover resources
// without querying Azure by name patterns. Eliminates coupling to naming conventions.

output resourceMetadata object = {
  storageAccountName: storageAccount.name
  storageAccountId: storageAccount.id
  containerName: containerName
  resourceGroup: split(storageAccount.id, '/')[4]
  location: location
}

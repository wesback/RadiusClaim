// RadiusClaim — Radius recipe: Azure Service Bus pub/sub broker
//
// Recipe name: 'pubsubrc' (abbreviation: pub/sub recipe)
// Dapr component type: 'pubsub.azure.servicebus/v1'
//
// ────────────────────────────────────────────────────────────────────────────
// WHAT IT DOES
// ────────────────────────────────────────────────────────────────────────────
// 1. Provisions an Azure Service Bus Namespace (naming: pubsubrc{randomSuffix})
// 2. Configures Entra workload identity authentication (SAS auth disabled)
// 3. Emits metadata for the Dapr pub/sub component (namespace name, endpoint)
//
// ────────────────────────────────────────────────────────────────────────────
// HOW IT INTEGRATES WITH DAPR
// ────────────────────────────────────────────────────────────────────────────
// Workload flow:
//   1. app.bicep defines a 'pubsub' connection to this recipe
//   2. Radius deploys the recipe, creating the Service Bus namespace
//   3. Radius creates a Dapr component (CRD) with:
//      - name: 'pubsub'
//      - type: 'pubsub.azure.servicebus/v1'
//      - metadata: { namespaceName, endpoint, ... }
//   4. Dapr sidecar in workload pods auto-discovers the component
//   5. Publishers call Dapr Pub/Sub APIs (PublishEventAsync) to send events
//   6. Subscribers call Dapr Pub/Sub APIs (SubscribeTopicAsync) to consume events
//   7. Dapr routes messages through the sidecar to the Service Bus namespace
//
// ────────────────────────────────────────────────────────────────────────────
// AUTHENTICATION & SECURITY
// ────────────────────────────────────────────────────────────────────────────
// - Authentication: Microsoft Entra workload identity (Dapr sidecar → Service Bus)
// - SAS/connection string auth is explicitly DISABLED (Azure Policy compliance)
// - Role: Azure Service Bus Data Owner (assigned to Dapr managed identity)
// - TLS: Minimum TLS 1.2 enforced
//
// Radius injects `context` automatically when the recipe runs.

@description('Radius-provided deployment context (injected by the platform).')
param context object

@description('Azure region for the Service Bus namespace. Supplied by environment recipe parameters.')
param location string

@description('Service Bus SKU tier.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

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
var namespaceName = 'pubsubrc${nameSuffix}'

// ---------------------------------------------------------------------------
// Service Bus Namespace
// ---------------------------------------------------------------------------

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: true
  }
}

// ---------------------------------------------------------------------------
// RBAC — Azure Service Bus Data Owner for Dapr workload identity
// ---------------------------------------------------------------------------

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, daprPrincipalId, '090c5cfd-751d-490a-894a-3ce6f1109419')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419') // Azure Service Bus Data Owner
    principalId: daprPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Dapr Component CRD — pubsub.azure.servicebus.topics
// ---------------------------------------------------------------------------
// NOTE: Dapr component is created separately (e.g., by deployment-dapr-components-workload-identity.sh)
// This recipe outputs metadata for the component; Radius does not manage the K8s resource itself.

var daprComponentName = 'pubsub'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------

output values object = {
  namespaceName: serviceBusNamespace.name
  endpoint: '${serviceBusNamespace.name}.servicebus.windows.net'
  componentName: daprComponentName
}

output resources array = [
  serviceBusNamespace.id
]

// ---------------------------------------------------------------------------
// Structured metadata for declarative resource discovery
// ---------------------------------------------------------------------------
// Consumed by bootstrap.sh and other platform automation to discover resources
// without querying Azure by name patterns. Eliminates coupling to naming conventions.

output resourceMetadata object = {
  serviceBusNamespaceName: serviceBusNamespace.name
  serviceBusNamespaceId: serviceBusNamespace.id
  endpoint: '${serviceBusNamespace.name}.servicebus.windows.net'
  resourceGroup: split(serviceBusNamespace.id, '/')[4]
  location: location
}

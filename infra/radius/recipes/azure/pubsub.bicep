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

@description('Client (application) ID of the Dapr workload identity for component auth metadata.')
param daprClientId string = ''

@description('Azure environment (cloud). Options: AzurePublicCloud, AzureUSGovernment, AzureChina. Defaults to AzurePublicCloud for sovereign cloud support.')
param azureEnvironment string = 'AzurePublicCloud'

@description('Azure subscription ID for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureSubscriptionId string

@description('Azure resource group name for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureResourceGroupName string

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id)
var namespaceName = 'pubsubrc${nameSuffix}'

// Explicit Azure resource ID — bypasses Radius deployment engine UCP scope resolution
var serviceBusArmId = '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroupName}/providers/Microsoft.ServiceBus/namespaces/${namespaceName}'

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
// Removed from recipe: Radius v0.56 bicep-de cannot authenticate nested ARM
// deployments created by cross-scope modules (scope: resourceGroup(sub, rg)).
// RBAC is assigned post-deploy by bootstrap.sh via `az role assignment create`.

// ---------------------------------------------------------------------------
// Dapr Component Metadata — pubsub.azure.servicebus.topics
// ---------------------------------------------------------------------------
// Radius recipes provision Azure resources only; Kubernetes CRDs (Dapr components)
// are created by the bootstrap script using the metadata outputted below.
// This separation follows Radius architecture: recipes = Azure provisioning,
// bootstrap = Kubernetes configuration.

var daprComponentName = 'pubsub'
var normalizedAzureEnvironment = toLower(azureEnvironment)
var serviceBusDnsSuffix = normalizedAzureEnvironment == 'azureusgovernment'
  ? 'servicebus.usgovcloudapi.net'
  : normalizedAzureEnvironment == 'azurechina'
    ? 'servicebus.chinacloudapi.cn'
    : 'servicebus.windows.net'
var daprEnvironmentName = azureEnvironment == 'AzureUSGovernment'
  ? 'AzureUSGovernmentCloud'
  : azureEnvironment == 'AzureChina'
    ? 'AzureChinaCloud'
    : 'AzurePublicCloud'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------

output values object = {
  namespaceName: '${serviceBusNamespace.name}.${serviceBusDnsSuffix}'
  endpoint: '${serviceBusNamespace.name}.${serviceBusDnsSuffix}'
  componentName: daprComponentName
  azureEnvironment: daprEnvironmentName
}

// Omit explicit `output resources` — Radius auto-populates from ARM deployment.

// ---------------------------------------------------------------------------
// Structured metadata for declarative resource discovery
// ---------------------------------------------------------------------------
// Consumed by bootstrap.sh and other platform automation to discover resources
// without querying Azure by name patterns. Eliminates coupling to naming conventions.

output resourceMetadata object = {
  serviceBusNamespaceName: serviceBusNamespace.name
  serviceBusNamespaceId: serviceBusArmId
  endpoint: '${serviceBusNamespace.name}.${serviceBusDnsSuffix}'
  resourceGroup: azureResourceGroupName
  location: location
  // Dapr component metadata for bootstrap script
  dapr: {
    componentName: daprComponentName
    componentType: 'pubsub.azure.servicebus.topics'
    componentVersion: 'v1'
    metadata: {
      namespaceName: '${serviceBusNamespace.name}.${serviceBusDnsSuffix}'
      azureClientId: daprClientId
      azureEnvironment: daprEnvironmentName
      disableEntityManagement: 'false'
    }
  }
}

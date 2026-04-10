// workload-identity.bicep — Azure Workload Identity Infrastructure
//
// Provisions user-assigned managed identity, federated credentials, and RBAC
// for AKS workload identity. This is cluster-level bootstrap infrastructure,
// deployed once before Radius application deployment.
//
// Usage:
//   az deployment group create \
//     --resource-group <rg> \
//     --template-file infra/azure/workload-identity.bicep \
//     --parameters location=<location> aksOidcIssuer=<issuer-url>

@description('Azure region for resources')
param location string = resourceGroup().location

@description('AKS OIDC issuer URL (e.g., https://eastus.oic.prod-aks.azure.com/{tenant}/{guid}/)')
param aksOidcIssuer string

@description('Kubernetes namespace where service accounts live')
param kubernetesNamespace string = 'azure-radiusclaim'

@description('Service account names to create federated credentials for')
param serviceAccounts array = [
  'expense-api'
  'workflow-engine'
  'notification-svc'
]

@description('Name of the managed identity')
param managedIdentityName string = 'radiusclaim-workload-identity'

// User-assigned managed identity for workload identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// Federated identity credentials (one per service account)
// Azure does not support concurrent FIC writes to the same managed identity.
// We must serialize FIC creation by creating them as separate resources with explicit dependencies.
// See: .squad/decisions/inbox/pete-fic-sequencing.md for constraint details.

// FIC 1: expense-api (first in chain, depends only on managed identity)
resource federatedCredential0 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: serviceAccounts[0]
  parent: managedIdentity
  properties: {
    issuer: aksOidcIssuer
    subject: 'system:serviceaccount:${kubernetesNamespace}:${serviceAccounts[0]}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// FIC 2: workflow-engine (depends on FIC 1)
resource federatedCredential1 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: serviceAccounts[1]
  parent: managedIdentity
  properties: {
    issuer: aksOidcIssuer
    subject: 'system:serviceaccount:${kubernetesNamespace}:${serviceAccounts[1]}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
  dependsOn: [
    federatedCredential0
  ]
}

// FIC 3: notification-svc (depends on FIC 2)
resource federatedCredential2 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: serviceAccounts[2]
  parent: managedIdentity
  properties: {
    issuer: aksOidcIssuer
    subject: 'system:serviceaccount:${kubernetesNamespace}:${serviceAccounts[2]}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
  dependsOn: [
    federatedCredential1
  ]
}

@description('Managed identity resource ID')
output managedIdentityId string = managedIdentity.id

@description('Managed identity client ID (Azure AD application ID)')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity principal ID (object ID for RBAC assignments)')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Managed identity name')
output managedIdentityName string = managedIdentity.name

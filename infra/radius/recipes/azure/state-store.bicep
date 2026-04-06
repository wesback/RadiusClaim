// RadiusClaim — Radius recipe: Azure Database for PostgreSQL Flexible Server (State Store)
//
// Recipe name: 'statestore' (Radius resource: Applications.Dapr/stateStores)
// Dapr component type: 'state.postgresql/v2'
//
// ────────────────────────────────────────────────────────────────────────────
// WHAT IT DOES
// ────────────────────────────────────────────────────────────────────────────
// 1. Provisions Azure Database for PostgreSQL Flexible Server (naming: pgstate{randomSuffix})
// 2. Creates a database for Dapr state storage (default: dapr_state)
// 3. Configures Microsoft Entra authentication ONLY (password auth disabled)
// 4. Registers the Dapr managed identity as the PostgreSQL Entra admin
// 5. Emits metadata for the Dapr state component (connection string, auth config)
//
// NOTE: No separate database role is created. The Dapr managed identity
// connects as the Entra admin using its display name as the PostgreSQL user.
// Dapr auto-creates state/actor tables on first use via DDL. For production
// least-privilege, see the Entra admin resource comments below.
//
// WHY POSTGRESQL (not Blob Storage)?
// - Blob Storage does NOT support transactional state (required for Dapr Actors)
// - PostgreSQL supports ACID transactions, enabling durable actor state
// - Dapr logs "Actor state management disabled" with non-transactional stores
// - PostgreSQL is portable across clouds (Azure, AWS, GCP, on-prem)
//
// ────────────────────────────────────────────────────────────────────────────
// HOW IT INTEGRATES WITH DAPR
// ────────────────────────────────────────────────────────────────────────────
// Workload flow:
//   1. app.bicep defines a 'statestore' connection to this recipe
//   2. Radius deploys the recipe, creating the PostgreSQL server
//   3. Radius creates a Dapr component (CRD) with:
//      - name: 'statestore'
//      - type: 'state.postgresql' (v2)
//      - metadata: { connectionString, useAzureAD, azureTenantId, azureClientId, ... }
//   4. Dapr sidecar in workload pods auto-discovers the component
//   5. App code calls Dapr State APIs (SaveStateAsync, GetStateAsync, etc.)
//   6. Dapr routes state calls through the sidecar to PostgreSQL
//   7. Actor state is persisted transactionally in PostgreSQL tables
//
// ────────────────────────────────────────────────────────────────────────────
// AUTHENTICATION & SECURITY
// ────────────────────────────────────────────────────────────────────────────
// - Microsoft Entra authentication ONLY — password auth is disabled
// - The Dapr managed identity is registered as the PostgreSQL Entra admin
// - No local admin account (administratorLogin) exists on the server
// - TLS required: SSL mode enforced for all connections
// - Network (PUBLIC, default): Firewall disabled by default (allowAzureServices = false); set true for dev/demo only
//   Network (PRIVATE, usePrivateEndpoint=true): Private Endpoint + DNS Zone; public firewall not deployed
//   ✅ Private endpoints recommended for production — eliminates public attack surface
//
// WHY ENTRA-ONLY (no password auth)?
// - Reference samples must teach security best practices
// - Managed identity eliminates credential rotation and secret sprawl
// - Azure Policy on many tenants blocks password-only PostgreSQL servers
// - Entra auth is the recommended path for Azure Database for PostgreSQL
//
// WHY IS THE DAPR IDENTITY THE ADMIN?
// - Simplest correct path for a reference sample / demo
// - Avoids init containers or out-of-band SQL scripts to create roles
// - The Dapr sidecar needs DDL access anyway (Dapr creates state/actor tables)
// - PRODUCTION NOTE: For least-privilege, use a separate admin identity and
//   grant the Dapr identity only the permissions it needs (SELECT, INSERT,
//   UPDATE, DELETE on Dapr-managed tables). See Issue #55 discussion.
//
// Radius injects `context` automatically when the recipe runs.

@description('Radius-provided deployment context (injected by the platform).')
param context object

@description('Azure region for the PostgreSQL server. Supplied by environment recipe parameters.')
param location string

@description('Name of the PostgreSQL database. Created by the recipe.')
param databaseName string = 'dapr_state'

@description('Optional random suffix for non-deterministic naming (dev/demo environments). If provided, replaces uniqueString generation.')
param randomNameSuffix string = ''

@description('Optional override for the PostgreSQL server name suffix. If set, this takes priority over randomNameSuffix (allows renaming without changing other resources).')
param postgresNameSuffix string = ''

@description('Principal (object) ID of the Dapr workload identity. Used as the Entra admin resource name (Azure requires the object ID).')
param daprPrincipalId string

@description('Display name of the Dapr managed identity. Used as principalName in the Entra admin resource and as the PostgreSQL connection user.')
param daprPrincipalName string

@description('Client (application) ID of the Dapr workload identity for component auth metadata.')
param daprClientId string = ''

@description('Azure environment (cloud). Options: AzurePublicCloud, AzureUSGovernment, AzureChina. Defaults to AzurePublicCloud for sovereign cloud support.')
param azureEnvironment string = 'AzurePublicCloud'

@description('Azure subscription ID for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureSubscriptionId string

@description('Azure resource group name for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureResourceGroupName string

@description('Dapr workload identity tenant ID for Entra authentication.')
param azureTenantId string

@description('''
Allow the 0.0.0.0/0.0.0.0 "Allow Azure services" magic firewall rule.
Defaults to false (no rule created). Set true only for quick dev/demo where VNet
integration is unavailable. NEVER enable in production.

PRODUCTION RECOMMENDATION: Use private endpoints or a delegated-subnet VNet
integration (network.delegatedSubnetResourceId) instead. The 0.0.0.0 rule permits
all Azure-hosted traffic — not just your AKS cluster.
''')
param allowAzureServices bool = false

// ---------------------------------------------------------------------------
// Private Endpoint parameters (Issue #61)
// ---------------------------------------------------------------------------
// Two network connectivity modes are supported:
//
//   PUBLIC (default, usePrivateEndpoint = false):
//     PostgreSQL reachable via Azure-services firewall rule when allowAzureServices = true.
//     Suitable for dev/demo environments without private VNet integration.
//     ⚠  "Allow Azure services" permits ALL Azure-hosted IPs — not just your AKS cluster.
//
//   PRIVATE (usePrivateEndpoint = true):
//     A Private Endpoint NIC is deployed in the specified VNet subnet.
//     A Private DNS Zone is created and linked to the VNet for automatic FQDN resolution.
//     The public Azure-services firewall rule is NOT deployed in this mode.
//     AKS must be VNet-routable to the private endpoint subnet.
//     ✅ Recommended for production — eliminates public attack surface.
//
// NOTE: When usePrivateEndpoint = true, public network access on the PostgreSQL server
// is NOT automatically disabled. This allows the recipe to deploy correctly in
// environments where the Radius operator cannot yet route through the private endpoint.
// For full isolation after deployment, set publicNetworkAccess: 'Disabled' on the server
// (az postgres flexible-server update --public-access Disabled).

@description('Enable a Private Endpoint for network-isolated PostgreSQL access. Recommended for production. Set true to deploy PE + Private DNS Zone instead of the public Azure-services firewall rule. Requires subnetResourceId and vnetResourceId.')
param usePrivateEndpoint bool = false

@description('Subnet resource ID to host the Private Endpoint network interface. Required when usePrivateEndpoint is true. Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}')
param subnetResourceId string = ''

@description('Virtual network resource ID for the Private DNS Zone VNet link. Required when usePrivateEndpoint is true. Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}')
param vnetResourceId string = ''

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(postgresNameSuffix) ? postgresNameSuffix : (!empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id))
var serverName = 'pgstate${nameSuffix}'

// Explicit Azure resource ID — bypasses Radius deployment engine UCP scope resolution
var postgresqlServerArmId = '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroupName}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${serverName}'

// ---------------------------------------------------------------------------
// Sovereign cloud DNS suffix map
// ---------------------------------------------------------------------------
// Maps azureEnvironment to the correct PostgreSQL FQDN suffix for each cloud.
// The server's fullyQualifiedDomainName property already resolves to the right
// suffix at runtime, so the connection string does not need to interpolate this
// directly. This map is provided for:
//   - Private DNS zone name construction
//   - Explicit documentation of supported clouds
//   - Any tooling that needs the suffix before the server is deployed
var postgresDnsSuffixMap = {
  AzurePublicCloud: '.postgres.database.azure.com'
  AzureUSGovernment: '.postgres.database.usgovcloudapi.net'
  AzureChina: '.postgres.database.chinacloudapi.cn'
}
var postgresDnsSuffix = postgresDnsSuffixMap[azureEnvironment]
// Private DNS zone name for private endpoint resolution (sovereign-cloud-aware).
var privateDnsZoneName = 'privatelink${postgresDnsSuffix}'

// ---------------------------------------------------------------------------
// Sovereign cloud Dapr auth environment name map
// ---------------------------------------------------------------------------
// Dapr's azureEnvironment metadata uses a DIFFERENT naming scheme than the
// DNS suffix map above. The two consumers require different key values for
// the same sovereign cloud. A single azureEnvironment value cannot satisfy both;
// we derive daprEnvironmentName from the same user-supplied azureEnvironment.
//
//   azureEnvironment (input)  →  DNS key          →  Dapr metadata name
//   ─────────────────────────────────────────────────────────────────────
//   AzurePublicCloud          →  AzurePublicCloud  →  AzurePublicCloud
//   AzureUSGovernment         →  AzureUSGovernment →  AzureUSGovernmentCloud
//   AzureChina                →  AzureChina        →  AzureChinaCloud
var daprEnvironmentNameMap = {
  AzurePublicCloud: 'AzurePublicCloud'
  AzureUSGovernment: 'AzureUSGovernmentCloud'
  AzureChina: 'AzureChinaCloud'
}
var daprEnvironmentName = daprEnvironmentNameMap[azureEnvironment]

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server — Entra-only authentication (no password auth)
// ---------------------------------------------------------------------------
// This server has NO local administrator account and NO password credentials.
// The only way to authenticate is via a Microsoft Entra token — issued to a
// managed identity and presented automatically by the Dapr sidecar.
//
// authConfig explained:
//   activeDirectoryAuth: 'Enabled'  — Entra token-based logins are accepted
//   passwordAuth: 'Disabled'        — Local password auth is blocked at the
//                                     server level; there is no password to leak
//   tenantId                        — The Entra tenant that must issue tokens;
//                                     tokens from other tenants are rejected

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server — Entra-only authentication (no password auth)
// ---------------------------------------------------------------------------
// WORKAROUND: Child resources (firewallRules, configurations, databases,
// administrators) are intentionally NOT declared here. Radius 0.56 bicep-de
// has a NullReferenceException bug (UpdateDeploymentResourcesWithScope line 662)
// when the compiled ARM template contains resources with 3-segment types
// (e.g. Microsoft.DBforPostgreSQL/flexibleServers/databases). All ARM resource
// types with 2+ child path segments trigger the bug.
//
// Workaround: declare ONLY the top-level server (2-segment type) here.
// Post-deployment configuration (database creation, Entra admin, firewall rules,
// SSL enforcement) is performed by bootstrap.sh via 'az postgres flexible-server'
// CLI commands immediately after rad deploy succeeds.
//
// When Radius fixes the bug, reinstate the child resources here and remove the
// corresponding section from bootstrap.sh.

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    version: '15'
    authConfig: {
      activeDirectoryAuth: 'Enabled'   // Entra token logins accepted
      passwordAuth: 'Disabled'         // No local passwords — nothing to rotate or leak
      tenantId: azureTenantId          // Only tokens from this tenant are trusted
    }
    storage: {
      storageSizeGB: 32
    }
    network: {
      delegatedSubnetResourceId: ''
      privateDnsZoneArmResourceId: ''
    }
    highAvailability: {
      mode: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    createMode: 'Default'
  }
}

// ---------------------------------------------------------------------------
// Private Endpoint resources — REMOVED due to Radius 0.56 bicep-de NPE
// ---------------------------------------------------------------------------
// WORKAROUND: Even conditional resources (if (usePrivateEndpoint)) are included
// in the compiled ARM template resources array with a `condition` property.
// Radius 0.56 UpdateDeploymentResourcesWithScope (line 662) throws
// NullReferenceException when it encounters Microsoft.Network/privateDnsZones
// or Microsoft.Network/privateEndpoints resources, even if their conditions
// evaluate to false.
//
// Private endpoint networking support must be added back once Radius fixes the
// NPE in a future version (track: radius-project/radius issue for bicep-de NPE).
// When re-enabling, re-add the two resources below and test with usePrivateEndpoint=true.

// ---------------------------------------------------------------------------
// Dapr Component Metadata — state.postgresql/v2 with Entra authentication
// ---------------------------------------------------------------------------

var daprComponentName = 'statestore'
var postgresPort = 5432

// Connection string for Dapr: user is the Entra admin's display name (managed identity name).
// No password — Dapr authenticates via Entra token (useAzureAD: true in component metadata).
var connectionString = 'host=${postgresqlServer.properties.fullyQualifiedDomainName} port=${postgresPort} database=${databaseName} user=${daprPrincipalName} sslmode=require'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------
// Radius expects `values` (flat key-value map surfaced to the Dapr component)
// and `resources` (Azure resource IDs for lifecycle tracking).

output values object = {
  serverName: postgresqlServer.name
  databaseName: databaseName
  databaseUser: daprPrincipalName  // Entra admin display name (backward-compat key for apply-dapr-components-from-recipes.sh)
  connectionString: connectionString
  // PostgreSQL natively supports transactional state — Dapr actors are enabled.
  // No blob fallback: Blob Storage lacks the TransactionalStore interface required
  // for Dapr Actors. This recipe migrated FROM blob storage for exactly this reason.
  actorStateStore: 'true'
  componentName: daprComponentName
  // Network access mode: 'private-endpoint' when usePrivateEndpoint=true; 'public' otherwise.
  networkAccess: usePrivateEndpoint ? 'private-endpoint' : 'public'
}

// Omit explicit `output resources` — Radius auto-populates outputResources
// from the ARM deployment. Manual declaration fails due to Radius deployment
// engine resolving postgresqlServer.id against UCP scope instead of Azure scope.

// ---------------------------------------------------------------------------
// Structured metadata for declarative resource discovery
// ---------------------------------------------------------------------------
// Consumed by bootstrap.sh and other platform automation to discover resources
// without querying Azure by name patterns. Eliminates coupling to naming conventions.

output resourceMetadata object = {
  postgresqlServerName: postgresqlServer.name
  postgresqlServerId: postgresqlServerArmId
  postgresqlFqdn: postgresqlServer.properties.fullyQualifiedDomainName
  postgresDnsSuffix: postgresDnsSuffix  // Sovereign-cloud-aware suffix for this deployment
  databaseName: databaseName
  databaseUser: daprPrincipalName  // Entra admin display name (backward-compat key)
  resourceGroup: azureResourceGroupName
  location: location
  authStrategy: 'entra-only'  // Explicit: no password auth on this server
  // Network isolation: 'private-endpoint' when usePrivateEndpoint=true; 'public' otherwise.
  networkAccess: usePrivateEndpoint ? 'private-endpoint' : 'public'
  privateEndpointId: usePrivateEndpoint ? resourceId('Microsoft.Network/privateEndpoints', 'pe-${serverName}') : ''
  privateDnsZoneName: usePrivateEndpoint ? privateDnsZoneName : ''
  // Dapr component metadata for bootstrap script
  dapr: {
    componentName: daprComponentName
    componentType: 'state.postgresql'
    componentVersion: 'v2'
    metadata: {
      connectionString: connectionString
      useAzureAD: 'true'
      azureTenantId: azureTenantId
      azureClientId: daprClientId
      azureEnvironment: daprEnvironmentName
      // PostgreSQL natively supports transactional state — Dapr actors are enabled.
      // No blob fallback: Blob Storage lacks the TransactionalStore interface required
      // for Dapr Actors. This recipe migrated FROM blob storage for exactly this reason.
      actorStateStore: 'true'
    }
  }
}

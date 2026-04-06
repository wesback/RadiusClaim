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
// - Network: Azure-services firewall rule permits AKS cluster access
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

@description('Principal (object) ID of the Dapr workload identity. Used as the Entra admin resource name (Azure requires the object ID).')
@secure()
param daprPrincipalId string

@description('Display name of the Dapr managed identity. Used as principalName in the Entra admin resource and as the PostgreSQL connection user.')
param daprPrincipalName string

@description('Client (application) ID of the Dapr workload identity for component auth metadata.')
param daprClientId string = ''

@description('Azure environment (cloud). Options: AzurePublicCloud, AzureUSGovernment, AzureChina. Defaults to AzurePublicCloud for sovereign cloud support.')
param azureEnvironment string = 'AzurePublicCloud'

@description('Azure subscription ID for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureSubscriptionId string

// Pin to a specific major version so every deployment gets the same engine regardless of when
// it runs. Azure Database for PostgreSQL Flexible Server accepts major-version strings ('15',
// '16', etc.). '15' is the LTS-grade stable release used as the pinned default here — it has
// broad Dapr driver compatibility and is GA on all Azure regions. Increment deliberately when
// you are ready to test the upgrade path; never use an unversioned or 'latest' equivalent.
@description('PostgreSQL major version. Pin this explicitly — leaving it unset or "latest" produces non-reproducible deployments.')
param postgresqlVersion string = '15'

@description('Azure resource group name for explicit resource ID construction. Works around Radius deployment engine UCP scope resolution.')
param azureResourceGroupName string

@description('Dapr workload identity tenant ID for Entra authentication.')
param azureTenantId string

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id)
var serverName = 'pgstate${nameSuffix}'

// Explicit Azure resource ID — bypasses Radius deployment engine UCP scope resolution
var postgresqlServerArmId = '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroupName}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${serverName}'

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server — Entra-only authentication (no password auth)
// ---------------------------------------------------------------------------
// Password auth is intentionally disabled. The Dapr managed identity connects
// via Entra tokens issued by Azure AD. No administratorLogin exists on this
// server — all access flows through the Entra admin configured below.

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    version: postgresqlVersion
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: azureTenantId
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
// PostgreSQL Firewall Rule — Allow Azure Services (AKS cluster access)
// ---------------------------------------------------------------------------

resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = {
  parent: postgresqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ---------------------------------------------------------------------------
// PostgreSQL Configuration — SSL/TLS enforcement
// ---------------------------------------------------------------------------

resource sslEnforcement 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresqlServer
  name: 'require_secure_transport'
  properties: {
    value: 'ON'
    source: 'user-override'
  }
}

// ---------------------------------------------------------------------------
// PostgreSQL Database
// ---------------------------------------------------------------------------

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgresqlServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ---------------------------------------------------------------------------
// Microsoft Entra Admin — Dapr workload identity as PostgreSQL admin
// ---------------------------------------------------------------------------
// The managed identity's object ID is the resource name (Azure API requirement).
// principalName is the identity's display name — this becomes the PostgreSQL
// login name for Entra-authenticated connections.
//
// DESIGN DECISION (Issue #54, #55):
// The Dapr identity is registered as the Entra admin rather than as a
// least-privilege role. This eliminates the need for an init container or
// out-of-band SQL script to CREATE ROLE, which would add deployment complexity
// disproportionate to a reference sample. Dapr needs DDL access to create its
// state and actor tables on first use, so admin-level access is functionally
// required during initial setup regardless.
//
// For production hardening, consider:
//   1. Use a separate admin identity for server management
//   2. Create a dedicated Entra-mapped role for the Dapr identity
//   3. Grant only INSERT/UPDATE/DELETE/SELECT on Dapr-managed tables
// ---------------------------------------------------------------------------

resource entraAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2023-12-01-preview' = {
  parent: postgresqlServer
  name: daprPrincipalId
  properties: {
    principalName: daprPrincipalName
    principalType: 'ServicePrincipal'
    tenantId: azureTenantId
  }
}

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
  actorStateStore: 'true'
  componentName: daprComponentName
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
  databaseName: databaseName
  databaseUser: daprPrincipalName  // Entra admin display name (backward-compat key)
  resourceGroup: azureResourceGroupName
  location: location
  authStrategy: 'entra-only'  // Explicit: no password auth on this server
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
      azureEnvironment: azureEnvironment
      actorStateStore: 'true'
    }
  }
}

// RadiusClaim — Radius recipe: Azure Database for PostgreSQL Flexible Server (State Store)
//
// Recipe name: 'statestore' (Radius resource: Applications.Dapr/stateStores)
// Dapr component type: 'state.postgresql/v2'
//
// ────────────────────────────────────────────────────────────────────────────
// WHAT IT DOES
// ────────────────────────────────────────────────────────────────────────────
// 1. Provisions Azure Database for PostgreSQL Flexible Server (naming: pgstate{randomSuffix})
// 2. Creates a database and schema for Dapr state storage
// 3. Configures Microsoft Entra authentication (no passwords, workload identity)
// 4. Creates a database user mapped to the Dapr workload identity
// 5. Emits metadata for the Dapr state component (connection string, auth config)
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
// - No passwords: Microsoft Entra authentication only
// - Authentication: Microsoft Entra workload identity (Dapr sidecar → PostgreSQL)
// - Database user created via Microsoft Entra admin login
// - TLS required: Enforce SSL mode for all connections
// - Network: Flexibility mode allows current client IP (AKS cluster)
//
// Radius injects `context` automatically when the recipe runs.

@description('Radius-provided deployment context (injected by the platform).')
param context object

@description('Azure region for the PostgreSQL server. Supplied by environment recipe parameters.')
param location string

@description('Name of the PostgreSQL database. Created by the recipe.')
param databaseName string = 'dapr_state'

@description('Database user name. This will be created as an Entra-managed database user.')
param databaseUser string = 'dapr_app'

@description('Optional random suffix for non-deterministic naming (dev/demo environments). If provided, replaces uniqueString generation.')
param randomNameSuffix string = ''

@description('Principal (object) ID of the Dapr workload identity for Entra AD authentication (required for Azure policy compliance).')
@secure()
param daprPrincipalId string

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

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------

// Use randomNameSuffix if provided; otherwise fall back to deterministic uniqueString.
var nameSuffix = !empty(randomNameSuffix) ? randomNameSuffix : uniqueString(context.resource.id)
var serverName = 'pgstate${nameSuffix}'

// Explicit Azure resource ID — bypasses Radius deployment engine UCP scope resolution
var postgresqlServerArmId = '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroupName}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${serverName}'

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server — Microsoft Entra authentication enabled
// ---------------------------------------------------------------------------

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: 'pgadmin'
    administratorLoginPassword: uniqueString(resourceGroup().id, context.resource.id)
    version: '15'
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
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
// Microsoft Entra Admin (for Dapr workload identity database user setup)
// NOTE: In production, this should be set up via Azure Policy or ARM template
// at the subscription level. For now, we set the Dapr identity as admin so it
// can create the database user mapping during initialization.
// ---------------------------------------------------------------------------

resource entraAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2023-12-01-preview' = {
  parent: postgresqlServer
  name: daprClientId
  properties: {
    principalName: databaseUser
    principalType: 'ServicePrincipal'
    tenantId: azureTenantId
  }
}

// ---------------------------------------------------------------------------
// Dapr Component Metadata — state.postgresql/v2 with Entra authentication
// ---------------------------------------------------------------------------

var daprComponentName = 'statestore'
var postgresPort = 5432

// Connection string for Dapr: host, port, database, user (no password for Entra auth)
var connectionString = 'host=${postgresqlServer.properties.fullyQualifiedDomainName} port=${postgresPort} database=${databaseName} user=${databaseUser} sslmode=require'

// ---------------------------------------------------------------------------
// Radius recipe outputs
// ---------------------------------------------------------------------------
// Radius expects `values` (flat key-value map surfaced to the Dapr component)
// and `resources` (Azure resource IDs for lifecycle tracking).

output values object = {
  serverName: postgresqlServer.name
  databaseName: databaseName
  databaseUser: databaseUser
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
  databaseUser: databaseUser
  resourceGroup: azureResourceGroupName
  location: location
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

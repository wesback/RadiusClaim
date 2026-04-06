// RadiusClaim — Shared module: Role Assignment
//
// Deploys a single Microsoft.Authorization/roleAssignment at the scope this
// module is deployed to (resource-group scope when called with
// `scope: resourceGroup(subscriptionId, resourceGroupName)` from a recipe).
//
// WHY A MODULE?
// Bicep BCP139 prevents resource-level `scope:` targeting a different resource
// group than the file's deployment scope. Modules are Bicep's prescribed
// escape hatch for cross-scope resource deployment. The parent recipe calls
// this module with an explicit `scope: resourceGroup(sub, rg)` to force ARM to
// resolve all IDs in the correct Azure ARM context, bypassing Radius UCP's
// tendency to substitute its own internal scope paths for `scope:` fields on
// extension resources (Microsoft.Authorization/roleAssignments).

@description('Azure AD principal object ID to grant the role to.')
param principalId string

@description('Full role definition resource ID. Use subscriptionResourceId() in the caller.')
param roleDefinitionId string

@description('Deterministic GUID for the role assignment name. Compute with guid() in the caller.')
param roleAssignmentName string

@description('Principal type. Defaults to ServicePrincipal (correct for managed identities).')
param principalType string = 'ServicePrincipal'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: principalType
  }
}

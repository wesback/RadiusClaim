@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

// Suppress unused-param warning — context is required by Radius but not consumed by in-cluster recipes.
var _ = context

// secretstores.kubernetes reads directly from Kubernetes secrets in the pod namespace.
// No backing infrastructure is provisioned and no metadata is required.
output result object = {
  values: {
    type: 'secretstores.kubernetes'
    version: 'v1'
    metadata: {}
  }
}

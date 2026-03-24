extension radius

@description('The Radius application ID that owns this container.')
param application string

@description('The Radius environment ID that owns this container.')
param environment string

@description('Logical service name and Radius container resource name.')
param name string

@description('Container image reference for the service.')
param image string

@description('Radius resource location.')
param location string = 'global'

@description('Primary HTTP port exposed by the service.')
param containerPort int = 8080

@description('Environment variables to inject into the container.')
param env object = {}

@description('Radius connections to supporting services or Dapr components.')
param connections object = {}

@description('Whether to enable a Dapr sidecar for the service.')
param enableDapr bool = true

@description('Dapr app ID for the service.')
param daprAppId string = name

@description('Port exposed to the Dapr sidecar.')
param daprAppPort int = containerPort

resource service 'Radius.Compute/containers@2025-08-01-preview' = {
  name: name
  location: location
  properties: union({
    environment: environment
    application: application
    containers: {
      '${name}': {
        image: image
        env: env
        ports: {
          http: {
            containerPort: containerPort
            protocol: 'TCP'
          }
        }
      }
    }
    connections: connections
  }, enableDapr
    ? {
        extensions: {
          daprSidecar: {
            appId: daprAppId
            appPort: daprAppPort
          }
        }
      }
    : {})
}

output id string = service.id

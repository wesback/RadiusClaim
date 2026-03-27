extension radius

@description('Radius local environment name.')
param environmentName string = 'local'

@description('Kubernetes namespace used for the local Radius development slice.')
param kubernetesNamespace string = 'radiusclaim-local'

@description('OCI registry prefix that stores published Radius local recipe artifacts.')
param recipeRegistry string = 'ghcr.io/wesback/radiusclaim/recipes/local'

@description('OCI tag used when resolving Radius local recipe artifacts.')
param recipeTag string = 'latest'

@description('Kubernetes namespace where Redis is deployed.')
param redisNamespace string = 'default'

@description('Redis service name within the cluster.')
param redisServiceName string = 'redis-master'

@description('Kubernetes namespace where RabbitMQ is deployed.')
param rabbitmqNamespace string = 'default'

@description('RabbitMQ service name within the cluster.')
param rabbitmqServiceName string = 'rabbitmq'

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: environmentName
  properties: {
    compute: {
      kind: 'kubernetes'
      resourceId: 'self'
      namespace: kubernetesNamespace
    }
    // No Azure provider — local recipes run entirely in-cluster.
    recipes: {
      'Applications.Dapr/stateStores': {
        'local-redis-state': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/state-store:${recipeTag}'
          parameters: {
            redisNamespace: redisNamespace
            redisServiceName: redisServiceName
          }
        }
      }
      'Applications.Dapr/pubSubBrokers': {
        'local-rabbitmq-pubsub': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/pubsub:${recipeTag}'
          parameters: {
            rabbitmqNamespace: rabbitmqNamespace
            rabbitmqServiceName: rabbitmqServiceName
          }
        }
      }
      'Applications.Dapr/secretStores': {
        'local-k8s-secrets': {
          templateKind: 'bicep'
          templatePath: '${recipeRegistry}/secrets:${recipeTag}'
        }
      }
    }
  }
}

output environmentModel object = {
  name: env.name
  computeTarget: 'local-kubernetes'
  namespace: kubernetesNamespace
  recipeArtifacts: {
    registry: recipeRegistry
    tag: recipeTag
  }
  recipes: {
    stateStore: 'local-redis-state'
    pubsub: 'local-rabbitmq-pubsub'
    secretStore: 'local-k8s-secrets'
  }
  note: 'No Azure provider configured. All Dapr components resolve to in-cluster Redis, RabbitMQ, and Kubernetes secrets.'
}

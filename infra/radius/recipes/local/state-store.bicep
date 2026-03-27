@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Kubernetes namespace where Redis is deployed.')
param redisNamespace string = 'default'

@description('Redis service name within the cluster.')
param redisServiceName string = 'redis-master'

@description('Redis port.')
param redisPort int = 6379

@description('Name of the Kubernetes secret holding the Redis password. Leave empty for unauthenticated Redis.')
param redisPasswordSecretName string = ''

@description('Key within the Kubernetes secret for the Redis password.')
param redisPasswordSecretKey string = 'redis-password'

// Suppress unused-param warning — context is required by Radius but not consumed by in-cluster recipes.
var _ = context

var redisHost = '${redisServiceName}.${redisNamespace}.svc.cluster.local:${redisPort}'

var baseMetadata = {
  redisHost: { value: redisHost }
  actorStateStore: { value: 'true' }
}

var authMetadata = empty(redisPasswordSecretName)
  ? {}
  : {
      redisPassword: {
        secretKeyRef: {
          name: redisPasswordSecretName
          key: redisPasswordSecretKey
        }
      }
    }

output result object = {
  values: {
    type: 'state.redis'
    version: 'v1'
    metadata: union(baseMetadata, authMetadata)
  }
}

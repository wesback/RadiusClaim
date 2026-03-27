@description('Radius-provided object containing information about the resource calling the Recipe.')
param context object

@description('Kubernetes namespace where RabbitMQ is deployed.')
param rabbitmqNamespace string = 'default'

@description('RabbitMQ service name within the cluster.')
param rabbitmqServiceName string = 'rabbitmq'

@description('RabbitMQ AMQP port.')
param rabbitmqPort int = 5672

@description('RabbitMQ username.')
param rabbitmqUser string = 'guest'

@description('Name of the Kubernetes secret holding the RabbitMQ password.')
param rabbitmqPasswordSecretName string = ''

@description('Key within the Kubernetes secret for the RabbitMQ password.')
param rabbitmqPasswordSecretKey string = 'rabbitmq-password'

// Suppress unused-param warning — context is required by Radius but not consumed by in-cluster recipes.
var _ = context

var host = 'amqp://${rabbitmqUser}@${rabbitmqServiceName}.${rabbitmqNamespace}.svc.cluster.local:${rabbitmqPort}'

var baseMetadata = {
  host: { value: host }
  durable: { value: 'true' }
  deletedWhenUnused: { value: 'false' }
  autoAck: { value: 'false' }
  reconnectWait: { value: '0' }
  concurrency: { value: 'parallel' }
}

var authMetadata = empty(rabbitmqPasswordSecretName)
  ? {}
  : {
      password: {
        secretKeyRef: {
          name: rabbitmqPasswordSecretName
          key: rabbitmqPasswordSecretKey
        }
      }
    }

output result object = {
  values: {
    type: 'pubsub.rabbitmq'
    version: 'v1'
    metadata: union(baseMetadata, authMetadata)
  }
}

// RadiusClaim — Radius application definition
//
// Deploy with:
//   rad deploy infra/radius/app.bicep \
//     --parameters containerRegistry=ghcr.io/wesback/radiusclaim \
//     --parameters imageTag=$(git rev-parse --short HEAD)
//
// The `environment` parameter is automatically injected by `rad deploy` from
// the active Radius workspace environment.  The environment must already exist
// (deployed via infra/radius/environments/azure-radius.bicep).
//
// Idempotent: re-running this deploy updates resources in place without leaving
// the system in a worse state.

extension radius

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Name of the Radius application.')
param applicationName string = 'radiusclaim'

@description('Container image registry base URL (no trailing slash).')
param containerRegistry string = 'ghcr.io/wesback/radiusclaim'

@description('Container image tag — typically the git commit SHA or semver string.')
param imageTag string

@description('Deployment target. Informational; passed by bootstrap to distinguish deploy modes.')
@allowed(['radius', 'local'])
#disable-next-line no-unused-params
param deploymentTarget string = 'radius'

@description('Set to true to add the azure.workload.identity/use label on workload pods. Passed as a string by rad deploy CLI.')
@allowed(['true', 'false'])
param useWorkloadIdentity string = 'true'

@description('''
Optional Kubernetes image pull secret name.
Leave empty when using public container registries (the default for RadiusClaim).
Pre-create the secret before deploying when set:
  kubectl create secret docker-registry ghcr-pull-secret ...
''')
param ghcrImagePullRef string = ''

@description('''
Dapr component recipe bindings.
Each recipeName must match a recipe registered in the active Radius environment
(infra/radius/environments/azure-radius.bicep).
bootstrap.sh reads daprBackings.secretStore.recipeName to compute the
deterministic Azure Key Vault name for the soft-delete preflight check.

State store is provisioned with PostgreSQL (supports transactional actors).
Pub/Sub is provisioned with Azure Service Bus.
Secret Store is provisioned with Azure Key Vault.
''')
param daprBackings object = {
  stateStore: {
    recipeName: 'azure-postgres-statestore'
  }
  pubSub: {
    recipeName: 'azure-servicebus-pubsub'
  }
  secretStore: {
    recipeName: 'azure-keyvault-secrets'
  }
}

@description('Radius environment resource ID. Injected automatically by rad deploy from the active workspace.')
param environment string

@description('Microsoft Entra ID authority URL for JWT bearer token validation (e.g. https://login.microsoftonline.com/{tenant-id}). Required in non-Development environments.')
param azureAdAuthority string = ''

@description('Microsoft Entra ID audience (API URI) for JWT bearer token validation (e.g. api://{client-id}). Required in non-Development environments.')
param azureAdAudience string = ''

// ---------------------------------------------------------------------------
// Shared computed values
// ---------------------------------------------------------------------------

var enableWorkloadIdentity = useWorkloadIdentity == 'true'

var wiExtension = enableWorkloadIdentity ? [
  {
    kind: 'kubernetesMetadata'
    labels: {
      'azure.workload.identity/use': 'true'
    }
  }
] : []

// Kubernetes runtime spec with resource requests/limits.
// Resources define container expectations: requests are used for scheduling,
// limits enforce upper bounds on resource consumption.
var kubernetesContainerResources = {
  resources: {
    requests: {
      cpu: '100m'
      memory: '128Mi'
    }
    limits: {
      cpu: '500m'
      memory: '256Mi'
    }
  }
}

// Pod-level runtimes block. Includes image pull secrets when supplied,
// and always includes container resource specifications.
var runtimesSpec = {
  kubernetes: {
    pod: {
      imagePullSecrets: !empty(ghcrImagePullRef) ? [
        { name: ghcrImagePullRef }
      ] : []
      containers: [
        union({
          name: 'app'
        }, kubernetesContainerResources)
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

resource app 'Applications.Core/applications@2023-10-01-preview' = {
  name: applicationName
  location: 'global'
  properties: {
    environment: environment
  }
}

// ---------------------------------------------------------------------------
// Dapr components — backed by Azure recipes registered in the environment
//
// All three resources use resourceProvisioning: 'recipe' (the default).
// type / version / metadata live inside the recipe Bicep; do NOT set them here —
// Radius rejects mixed manual+recipe declarations.
// ---------------------------------------------------------------------------

resource stateStore 'Applications.Dapr/stateStores@2023-10-01-preview' = {
  name: 'statestore'
  location: 'global'
  properties: {
    environment: environment
    application: app.id
    recipe: {
      name: daprBackings.stateStore.recipeName
    }
  }
}

resource pubSub 'Applications.Dapr/pubSubBrokers@2023-10-01-preview' = {
  name: 'pubsub'
  location: 'global'
  properties: {
    environment: environment
    application: app.id
    recipe: {
      name: daprBackings.pubSub.recipeName
    }
  }
}

resource platformSecrets 'Applications.Dapr/secretStores@2023-10-01-preview' = {
  name: 'platform-secrets'
  location: 'global'
  properties: {
    environment: environment
    application: app.id
    recipe: {
      name: daprBackings.secretStore.recipeName
    }
  }
}

// ---------------------------------------------------------------------------
// Workload: expense-api
//   Backend REST API. Reads/writes expense records via the Dapr state store,
//   publishes domain events via pub/sub, and reads credentials from the
//   secret store.  Dapr service invocation is used for inbound calls from
//   workflow-engine.
// ---------------------------------------------------------------------------

resource expenseApi 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'expense-api'
  location: 'global'
  properties: {
    application: app.id
    container: {
      image: '${containerRegistry}/expense-api:${imageTag}'
      env: {
        AzureAd__Authority: {
          value: !empty(azureAdAuthority) ? azureAdAuthority : '${az.environment().authentication.loginEndpoint}common'
        }
        AzureAd__Audience: {
          value: !empty(azureAdAudience) ? azureAdAudience : 'https://radiusclaim.azurewebsites.net/api'
        }
      }
      ports: {
        http: {
          containerPort: 8080
          protocol: 'TCP'
        }
      }
      readinessProbe: {
        kind: 'httpGet'
        containerPort: 8080
        path: '/healthz'
        initialDelaySeconds: 5
        failureThreshold: 5
        periodSeconds: 10
      }
      livenessProbe: {
        kind: 'httpGet'
        containerPort: 8080
        path: '/healthz'
        initialDelaySeconds: 15
        failureThreshold: 3
        periodSeconds: 20
      }
    }
    connections: {
      statestore: {
        source: stateStore.id
      }
      pubsub: {
        source: pubSub.id
      }
      platformSecrets: {
        source: platformSecrets.id
      }
    }
    extensions: concat(
      [
        {
          kind: 'daprSidecar'
          appId: 'expense-api'
          appPort: 8080
        }
      ],
      wiExtension
    )
    runtimes: runtimesSpec
  }
}

// ---------------------------------------------------------------------------
// Workload: workflow-engine
//   Dapr Workflow orchestration service. Manages long-running expense approval
//   workflows using Dapr Workflow APIs (actor-backed, state in the state store).
//   Publishes status events via pub/sub. Invokes expense-api via Dapr service
//   invocation using the stable app ID for approval decisions.
// ---------------------------------------------------------------------------

resource workflowEngine 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'workflow-engine'
  location: 'global'
  properties: {
    application: app.id
    container: {
      image: '${containerRegistry}/workflow-engine:${imageTag}'
      ports: {
        http: {
          containerPort: 8080
          protocol: 'TCP'
        }
      }
      readinessProbe: {
        kind: 'httpGet'
        containerPort: 8080
        path: '/healthz'
        initialDelaySeconds: 5
        failureThreshold: 5
        periodSeconds: 10
      }
      livenessProbe: {
        kind: 'httpGet'
        containerPort: 8080
        path: '/healthz'
        initialDelaySeconds: 15
        failureThreshold: 3
        periodSeconds: 20
      }
    }
    connections: {
      statestore: {
        source: stateStore.id
      }
      pubsub: {
        source: pubSub.id
      }
      platformSecrets: {
        source: platformSecrets.id
      }
    }
    extensions: concat(
      [
        {
          kind: 'daprSidecar'
          appId: 'workflow-engine'
          appPort: 8080
        }
      ],
      wiExtension
    )
    runtimes: runtimesSpec
  }
}

// ---------------------------------------------------------------------------
// Workload: notification-svc
//   Async notification service. Subscribes to domain events via the pub/sub
//   broker and dispatches notifications (email, webhook) to claim submitters.
//   Reads credentials from the secret store.
// ---------------------------------------------------------------------------

resource notificationSvc 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'notification-svc'
  location: 'global'
  properties: {
    application: app.id
    container: {
      image: '${containerRegistry}/notification-svc:${imageTag}'
      ports: {
        http: {
          containerPort: 8080
          protocol: 'TCP'
        }
      }
      readinessProbe: {
        kind: 'httpGet'
        containerPort: 8080
        path: '/healthz'
        initialDelaySeconds: 5
        failureThreshold: 5
        periodSeconds: 10
      }
      livenessProbe: {
        kind: 'httpGet'
        containerPort: 8080
        path: '/healthz'
        initialDelaySeconds: 15
        failureThreshold: 3
        periodSeconds: 20
      }
    }
    connections: {
      pubsub: {
        source: pubSub.id
      }
      platformSecrets: {
        source: platformSecrets.id
      }
    }
    extensions: concat(
      [
        {
          kind: 'daprSidecar'
          appId: 'notification-svc'
          appPort: 8080
        }
      ],
      wiExtension
    )
    runtimes: runtimesSpec
  }
}

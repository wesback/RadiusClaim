# Local Development Guide

This guide covers running RadiusClaim locally using Radius with **in-cluster components** — no Azure subscription required.

## Overview

RadiusClaim uses Radius recipes to abstract its Dapr components. Two recipe sets are available:

| Environment | State store | Pub/sub | Secrets |
|---|---|---|---|
| `azure` / `dev` | Azure Blob Storage | Azure Service Bus | Azure Key Vault |
| `local` | Redis (in-cluster) | RabbitMQ (in-cluster) | Kubernetes secrets |

Switching between them is a single parameter change at deploy time. The application code is unchanged.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or equivalent container runtime
- [kind](https://kind.sigs.k8s.io/) or [k3d](https://k3d.io/) for a local Kubernetes cluster
- [Radius CLI](https://docs.radapp.io/getting-started/) (`rad`)
- [Helm](https://helm.sh/) for installing Redis and RabbitMQ
- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/)

## 1 — Cluster Setup

```bash
# Create a local cluster (kind example)
kind create cluster --name radiusclaim

# Install Radius
rad install kubernetes

# Install Dapr
dapr init --kubernetes --wait
```

## 2 — Install In-Cluster Dependencies

The local recipes point to Redis and RabbitMQ by their Kubernetes service names. Install both with Helm:

```bash
# Redis — state store backend
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install redis bitnami/redis \
  --namespace default \
  --set auth.enabled=false \
  --set replica.replicaCount=0

# RabbitMQ — pub/sub backend
helm install rabbitmq bitnami/rabbitmq \
  --namespace default \
  --set auth.username=guest \
  --set auth.password=guest
```

The local recipes default to:
- Redis: `redis-master.default.svc.cluster.local:6379`
- RabbitMQ: `amqp://guest@rabbitmq.default.svc.cluster.local:5672`

Override `redisServiceName`, `redisNamespace`, `rabbitmqServiceName`, or `rabbitmqNamespace` in `local.parameters.json` if your Helm release names differ.

## 3 — Publish Local Recipes

Local recipes must be pushed to a container registry accessible from your cluster. For local clusters, use a registry bundled with kind/k3d:

```bash
# k3d example — creates cluster + registry in one step
k3d cluster create radiusclaim --registry-create radiusclaim-registry:5000

# Push local recipe images
az bicep publish \
  --file infra/radius/recipes/local/state-store.bicep \
  --target br:localhost:5000/recipes/local/state-store:latest

az bicep publish \
  --file infra/radius/recipes/local/pubsub.bicep \
  --target br:localhost:5000/recipes/local/pubsub:latest

az bicep publish \
  --file infra/radius/recipes/local/secrets.bicep \
  --target br:localhost:5000/recipes/local/secrets:latest
```

Then update `infra/radius/environments/local.parameters.json`:

```json
{
  "recipeRegistry": { "value": "localhost:5000/recipes/local" }
}
```

For CI environments using kind with GHCR access, you can keep the default `ghcr.io/wesback/radiusclaim/recipes/local` registry and publish recipes as part of the workflow.

## 4 — Deploy the Local Environment

```bash
# Register the local Radius environment
rad deploy infra/radius/environments/local.bicep \
  --parameters @infra/radius/environments/local.parameters.json

# Deploy the application using local recipe selections
rad deploy infra/radius/app.bicep \
  --environment local \
  --parameters containerRegistry=ghcr.io/wesback/radiusclaim \
  --parameters imageTag=dev \
  --parameters deploymentTarget=local \
  --parameters daprBackings='{"stateStore":{"recipeName":"local-redis-state","parameters":{}},"pubsub":{"recipeName":"local-rabbitmq-pubsub","parameters":{}},"secretStore":{"recipeName":"local-k8s-secrets","parameters":{}}}'
```

### Using a Parameters File

Create `infra/radius/app.local.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "containerRegistry": { "value": "ghcr.io/wesback/radiusclaim" },
    "imageTag": { "value": "dev" },
    "deploymentTarget": { "value": "local" },
    "daprBackings": {
      "value": {
        "stateStore": { "recipeName": "local-redis-state", "parameters": {} },
        "pubsub":     { "recipeName": "local-rabbitmq-pubsub", "parameters": {} },
        "secretStore": { "recipeName": "local-k8s-secrets", "parameters": {} }
      }
    }
  }
}
```

Then deploy with:

```bash
rad deploy infra/radius/app.bicep \
  --environment local \
  --parameters @infra/radius/app.local.parameters.json
```

## 5 — Kubernetes Secrets for Local Secret Store

The `local-k8s-secrets` recipe uses `secretstores.kubernetes` — Dapr reads secrets directly from Kubernetes in the pod's namespace. Create secrets the same way you'd create any Kubernetes secret:

```bash
kubectl create secret generic my-app-secret \
  --namespace radiusclaim-local \
  --from-literal=api-key=my-local-value
```

Application code accesses secrets through the Dapr secret API with the Kubernetes secret name and key.

## 6 — Verify the Deployment

```bash
# Check Radius environment
rad env show local

# List application resources
rad resource list Applications.Dapr/stateStores --application radiusclaim
rad resource list Applications.Dapr/pubSubBrokers --application radiusclaim
rad resource list Applications.Dapr/secretStores --application radiusclaim

# Check Dapr components loaded correctly
kubectl get components -n radiusclaim-local

# Check pod health
kubectl get pods -n radiusclaim-local
```

## Switching Back to Azure

To run against Azure resources, use the `dev` or `azure-radius` environment without overriding `daprBackings`:

```bash
rad deploy infra/radius/app.bicep \
  --environment dev \
  --parameters @infra/radius/dev.parameters.json
```

The `daprBackings` default in `app.bicep` points to Azure recipes — no additional flags needed.

## Troubleshooting

**Redis connection refused**: Confirm the Helm release name matches `redisServiceName` in `local.parameters.json`. Check with `kubectl get svc -n default | grep redis`.

**RabbitMQ auth errors**: The local recipe defaults to `guest` user and no password secret. If you installed RabbitMQ with a different username, set `rabbitmqUser` in `pubsub.bicep` or pass a custom parameters object via `daprBackings.pubsub.parameters`.

**Recipe template not found**: Ensure you've published the local recipe OCI artifacts to the registry configured in `local.parameters.json`. Run `az bicep publish` for all three recipes.

**Dapr component not loading**: Run `kubectl describe component statestore -n radiusclaim-local` for the full error. Common cause is the recipe outputting a Dapr component type (`state.redis`) that doesn't match the installed Dapr version.

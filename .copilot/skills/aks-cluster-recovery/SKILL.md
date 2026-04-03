# AKS Cluster Recovery: Image Pull & Dapr Component Wiring

**Classification:** Platform troubleshooting | Image registry auth | Kubernetes workload recovery

**Context:** Live AKS clusters with stale or unauthorized container image references, failed Dapr sidecar initialization, missing component configurations.

## Problem

Kubernetes deployments stuck in `ImagePullBackOff` or `Pending` due to:
1. Private container registries without AKS pull credentials
2. Stale image references (old registry namespaces, deprecated tags)
3. Dapr sidecars failing because app containers can't start
4. Dapr components missing from the cluster (indicates incomplete IaC deployment)

**Symptoms:**
```
$ kubectl describe pod <app-pod> -n <namespace>
Failed to pull image "ghcr.io/old-org/app:phase1": 403 Forbidden
$ kubectl get components -n <namespace>
# (empty or incomplete)
```

## Solution Pattern

### Step 1: Resolve Image Registry Access
Choose **one** approach:

**Option A: Make packages public (reference samples)**
```bash
gh api repos/$OWNER/$REPO/packages --paginate \
  --jq '.[] | select(.package_type == "container") | .name' \
  | while read pkg; do
    gh api repos/$OWNER/$REPO/packages/container/$pkg/access_policies \
      --method PATCH \
      -f visibility='public'
  done
```

**Option B: Create imagePullSecret (production)**
```bash
kubectl create secret docker-registry ghcr-credentials \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USERNAME" \
  --docker-password="$GITHUB_TOKEN" \
  -n "$NAMESPACE"

kubectl patch serviceaccount default -n "$NAMESPACE" \
  -p '{"imagePullSecrets": [{"name": "ghcr-credentials"}]}'
```

### Step 2: Redeploy with Correct Images
Use **kubectl set image** (non-disruptive, avoids editing manifests):

```bash
# Scale down to clear failed pods
kubectl scale deployment/$APP -n "$NAMESPACE" --replicas=0
sleep 10

# Update images with explicit tag
kubectl set image deployment/$APP \
  $APP="$NEW_REGISTRY/$APP:$EXPLICIT_TAG" \
  -n "$NAMESPACE" \
  --record

# Scale back up and monitor
kubectl scale deployment/$APP -n "$NAMESPACE" --replicas=1
kubectl rollout status deployment/$APP -n "$NAMESPACE" --timeout=5m
```

### Step 3: Verify Dapr Components
If using Radius/Dapr:
```bash
# Dapr components should be provisioned by IaC (Radius, Helm, manual manifests)
kubectl get components -n "$NAMESPACE"

# If missing, re-run Radius environment deployment:
./rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters kubernetesNamespace="$NAMESPACE" \
  --parameters location="$AZURE_LOCATION"
```

## Why This Works

1. **Registry auth first:** App can't start if it can't pull images; sidecars fail before components matter.
2. **Scale-down:** Clears `Pending` pods that have already failed image pull; forces fresh attempt on scale-up.
3. **kubectl set image:** Updates deployment spec without recreating; preserves all other config (labels, env vars, etc.).
4. **Explicit tag:** Prevents confusion from :latest; pins to exactly what was tested.
5. **Dapr via Radius/IaC:** Components are ownable by infrastructure code; manual creation diverges from intent.

## Validation

```bash
# Deployments ready
kubectl get deployment -n "$NAMESPACE" -w

# Pods running
kubectl get pods -n "$NAMESPACE"

# Correct images in use
kubectl get pods -n "$NAMESPACE" -o json \
  | jq '.items[] | {name: .metadata.name, image: .spec.containers[0].image}'

# Dapr sidecars healthy (if applicable)
kubectl get pods -n "$NAMESPACE" -o json \
  | jq '.items[] | {name: .metadata.name, sidecar_ready: (.status.containerStatuses[] | select(.name == "daprd") | .ready)}'
```

## Key Decisions

- **No hand-written K8s YAML:** Use Radius/Helm/IaC to manage Dapr components; avoids drift.
- **Public vs. private images:** For open samples, public is preferred. For production, imagePullSecret pattern.
- **One tag per environment:** Avoid :latest in production. Use git SHA (CI/CD) or semver.

## References

- [RadiusClaim Recovery Case](../../decisions/inbox/graham-recovery-commands.md) — Full walkthrough with copy-paste commands
- [Kubernetes Deployment image updates](https://kubernetes.io/docs/tasks/run-application/rolling-updates-deployment/)
- [Docker Registry Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)


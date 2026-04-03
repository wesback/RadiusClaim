# Rod — Radius UCP deletion diagnosis (2026-04-01)

## Findings

- `kubectl get pods -n radius-system` showed `ucp`, `applications-rp`, and `controller` all `Running` with `0` restarts.
- `kubectl rollout status` for those deployments succeeded, so this is not a controller crash-loop health issue.
- `rad resource show Applications.Dapr/secretStores platform-secrets` and `... stateStores statestore` both still existed in Radius with `properties.provisioningState: Failed` and `properties.environment` pointing to stale environment `radiusclaim-azure`.
- `rad resource show Applications.Core/applications radiusclaim` showed the live app bound to environment `azure`, confirming the Dapr resources were orphaned from the current environment.
- `kubectl get components -A | grep -Ei 'platform-secrets|statestore'` returned nothing, so there was no live Dapr Component CRD to delete in Kubernetes.
- UCP logs showed the key sequence:
  - DELETE accepted with HTTP `202` for `Applications.Dapr/secretStores/platform-secrets`
  - async worker retries for tracked resource `platform-secrets-...`
  - repeated `trackedresource/update.go:142` failures with `error: resource is still being provisioned`
  - final `worker.go:190` error `exceeded max retry count to process async operation message: 4`
- The same retry-limit pattern also appeared for `statestore`.

## Root cause

This is **resource in terminal/stuck control-plane state** (option 4), caused by Radius UCP repeatedly trying to process orphaned tracked resources whose stale environment no longer exists. It is **not** a reconciler crash loop, **not** queue saturation, and **not** primarily a Kubernetes finalizer deadlock because there is no corresponding Dapr Component CRD in the cluster.

## Script changes

Updated `scripts/bootstrap.sh`:

1. Added `wait_for_dapr_resource_deletion()` to reuse deletion verification logic.
2. Added `radius_controllers_healthy()` to detect unhealthy Radius deployments before cleanup proceeds.
3. Added `force_remove_dapr_component_finalizers()` as a last-resort fallback when a real `components.dapr.io` object exists with a deletion timestamp and finalizers.
4. Upgraded `delete_dapr_resource_with_verify()` to:
   - verify deletion for 60s,
   - diagnose controller health,
   - inspect the Radius resource's provisioning state and environment binding,
   - attempt finalizer removal only when a real Dapr component CRD is stuck,
   - run one final 30s verification poll,
   - emit `log_error` with actionable restart / force-delete / reinstall guidance if the resource still exists.
5. Because `platform-secrets` and `statestore` hit the same stuck-state signature, the same helper fix now covers both.

## Validation

- `bash -n scripts/bootstrap.sh` passed.

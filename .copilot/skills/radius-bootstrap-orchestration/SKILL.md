---
name: "radius-bootstrap-orchestration"
description: "Create an honest bootstrap script for a Kubernetes-first Radius app that wraps existing deployment helpers and proves post-backfill recovery"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a repo already has the pieces of a manual Radius deployment path (recipe publication, app deploy, validation, Dapr recovery helpers) but operators still have to remember the order, the stop points, and the post-deploy recovery sequence from tribal knowledge.

## Pattern

### Bootstrap by orchestration, not duplication

- The bootstrap script should call the existing helper scripts when they already own a slice of the flow.
- For RadiusClaim-style repos, the orchestrator should wrap:
  - recipe publication
  - Dapr component backfill
  - end-to-end validation
- Only inline the glue that does not already exist elsewhere: preflight checks, Radius workspace/group/environment setup, image build/push, rollout restart, and validation URL selection.

### Prove the prerequisites before mutating anything

Validate these layers in order:
1. Local tooling (`az`, `kubectl`, `rad`, `dapr`, `jq`, `docker`, `curl`)
2. Azure auth/subscription context
3. Kubernetes cluster reachability and Dapr/Radius control planes
4. Radius workspace/group/environment context
5. Existing deployment state (resource group, env/app presence, component presence, recipe registry access)

For Radius specifically, key the health check off the documented controller pod (`kubectl get pods -n radius-system -l app.kubernetes.io/name=controller`) instead of assuming a repo-local `control-plane=*` label that the stock install path may not stamp onto pods. If the script must tolerate older clusters, allow a fallback to the legacy `radius-controller-manager` naming.

### Keep idempotency honest

- Reuse stable Radius names and use `rad env create <name> || true`.
- Default to interactive confirmation when reusing an existing environment/app or creating a missing resource group.
- Use a single `--yes` override for non-interactive execution; do not silently convert destructive or identity-affecting actions into defaults.
- Never normalize the bootstrap path into an app delete / namespace delete loop. If an operator needs teardown, make that an explicit manual choice.

### Treat Dapr component backfill as part of the happy path

If the platform uses Radius recipes for `Applications.Dapr/*`, assume the Kubernetes `Component` CRDs may still need manual backfill.

After backfilling:
- verify the expected component names in the workload namespace
- restart the app deployments
- wait for rollout completion
- check sidecar logs for `Component loaded: ...` before declaring success

### Validate through the best reachable surface

- Prefer the Radius-managed public gateway when it is healthy.
- If the gateway is not ready yet, fall back to `kubectl port-forward` and still run the shared validation script so the flow evidence stays consistent.

## Examples

- Orchestrator: `scripts/bootstrap.sh`
- Helpers:
  - `scripts/publish-radius-recipes.sh`
  - `scripts/deploy-dapr-components.sh`
  - `scripts/validate-deployment.sh`
- Environment model: `infra/radius/environments/azure-radius.bicep`
- App model: `infra/radius/app.bicep`

## Anti-Patterns

- Re-implementing helper scripts inside the bootstrap wrapper
- Hiding registry defaults behind an unsafe fallback to someone else's GHCR namespace
- Treating Radius-recipe-backed Dapr resources as if Kubernetes automatically received `components.dapr.io`
- Declaring success after component apply without restarting workloads and proving sidecar recovery
- Using guessed control-plane selectors in preflight checks when the repo's install/troubleshooting docs already point to a specific controller label

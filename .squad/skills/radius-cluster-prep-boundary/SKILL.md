---
name: "radius-cluster-prep-boundary"
description: "Split first-time Kubernetes cluster preparation from repeatable Radius app deployment"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a Kubernetes-first Radius repo has grown a single bootstrap script that mixes cluster lifecycle concerns with repeatable environment/app deployment. The fix is to make the operator flow honest: cluster prep is one boundary, app deployment is another.

## Patterns

### Separate one-time cluster work from replayable deploy work

- Put AKS creation/reuse, `kubectl` context setup, Dapr install/preflight, Radius install/preflight, and Radius workspace/group selection in a dedicated cluster-prep script.
- Keep the deployment bootstrap focused on the repeatable layer: recipe publication, Radius environment deploy, app deploy, Dapr component backfill, and smoke validation.

### Gate infrastructure creation explicitly

- Default to verifying or reusing an AKS cluster.
- Require an explicit `--create-aks` flag before the script is allowed to provision a new cluster.
- Keep install actions (`--install-dapr`, `--install-radius`) explicit for non-interactive usage.
- In help text and operator docs, say plainly that omitting the install flags leaves Dapr/Radius in verify-only mode. First-time examples for fresh clusters should include both flags so the script's boundary stays teachable instead of feeling like a surprise failure.

### Keep verification in the repeatable path

- Even after the split, the repeatable bootstrap should still verify that `kubectl`, Dapr, and Radius are healthy before mutating app state.
- Verification is safe to rerun; cluster creation and control-plane installation are not.

## Examples

- First-time cluster prep: `scripts/prepare-cluster.sh`
- Repeatable deploy: `scripts/bootstrap.sh`
- Shared helpers: `scripts/lib/platform-common.sh`
- Operator docs: `scripts/README.md`, `docs/end-to-end-setup-walkthrough.md`

## Anti-Patterns

- Hiding AKS creation inside the repeatable deployment path.
- Letting `--yes` implicitly create a cluster when the operator never asked for AKS provisioning.
- Mixing Dapr/Radius control-plane installation with every app redeploy.
- Marking Dapr/Radius install flags as "optional" in first-time docs without explaining that the script will only verify and stop when those control planes are absent.
- Explaining the operator flow as one opaque script when the replay boundary is actually two different phases.

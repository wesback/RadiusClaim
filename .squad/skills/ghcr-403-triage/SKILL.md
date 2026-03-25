---
name: "ghcr-403-triage"
description: "Separate stale GHCR image references from real package-visibility or pull-auth problems in Radius/Kubernetes deployments"
domain: "platform"
confidence: "high"
source: "graham-earned"
tools:
  - name: "web_fetch"
    description: "Probe anonymous GHCR token endpoints to distinguish old owners from public packages"
    when: "When Kubernetes reports GHCR 401/403 and you need to classify whether the image path itself is stale"
---

## Context

Use this when a Radius-managed Kubernetes deployment gets `ImagePullBackOff`, `ErrImagePull`, or GHCR `403 Forbidden` and the question is whether the repo points at the wrong image path/tag versus the operator needing to fix package visibility or pull credentials.

## Patterns

### Check the deployed image reference before changing Radius models

- If pod events mention an old owner/tag pair such as `ghcr.io/sovereignapp/radiusclaim/*:phase1`, treat that as repo drift first.
- Fix the app model defaults so they point at the current repository namespace, and require an explicit image tag if the old default is no longer published.
- Do not reopen unrelated Radius namespace or recipe decisions just because the failure appears during `rad deploy`; image pulls are a later layer.

### Use GHCR anonymous token probes as a fast classifier

- Probe `https://ghcr.io/token?scope=repository:<owner>/<package>:pull&service=ghcr.io`.
- `403` for the old owner path is strong evidence the app model is pointing at a dead or unauthorized namespace.
- A token for one package under the current owner (for example recipe artifacts) proves the live namespace.
- `401` for the service-image package under the current owner usually means the package is missing or private; that is no longer a Bicep or Radius wiring bug.

### Keep manual and CI deploy tags explicit

- Workflow-driven publishes should pass the generated tag (for example commit SHA) into `rad deploy`.
- Manual operator docs should tell people to build/push first, then pass the exact same `containerRegistry` and `imageTag` values to `rad deploy`.
- Avoid nostalgic defaults like `phase1`; they silently route clusters to retired packages and make GHCR errors look like platform regressions.

### For private GHCR packages, prefer one clear operator path

- If the service-image packages are meant to stay private, document the namespace-scoped `docker-registry` secret + service account patch sequence.
- If they are meant to be public, tell operators to make the package public in GHCR and retry before adding more cluster glue.
- Keep this as operator-facing troubleshooting unless Radius grows a first-class registry-auth abstraction that is cleaner than Kubernetes `imagePullSecrets`.

## Examples

- App model: `infra/radius/app.bicep`
- Compiled contract: `infra/radius/app.json`
- Operator checklist: `docs/radius-validation-checklist.md`
- Walkthrough: `docs/end-to-end-setup-walkthrough.md`
- Publish workflow: `.github/workflows/deploy-azure.yml`

## Anti-Patterns

- Treating GHCR 403 as proof that the Radius namespace revert failed.
- Leaving stale image defaults in shared Bicep because "operators can override them anyway."
- Adding custom Kubernetes YAML before proving the image path/tag is current.
- Telling operators to retry `rad deploy` without checking whether the referenced package is public, private, or missing.

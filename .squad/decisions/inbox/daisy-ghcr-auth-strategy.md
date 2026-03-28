# Decision: GHCR Auth Strategy — Public Packages for Public Repo

**Date:** 2026-03-28
**Author:** Daisy (Lead)
**Status:** Accepted
**Scope:** Container image pull authentication for all deployment targets

## Context

All three RadiusClaim service images (`expense-api`, `workflow-engine`, `notification-svc`) are private on GHCR despite the repository being public. This causes `ImagePullBackOff` / `401 Unauthorized` on every deployment target — local Radius, CI-to-AKS, and fresh clusters.

The infrastructure plumbing for `imagePullSecrets` already exists (`app.bicep` → `container-service.bicep`), and `bootstrap.sh` already creates a `ghcr-pull-secret`. But this is ceremony that shouldn't be required for a public reference sample.

## Decision

**Make all GHCR service image packages public.** This is the correct default for a public reference architecture.

### Rationale

1. **Teachability:** A developer cloning this repo should be able to `rad deploy` without configuring GHCR credentials. Every extra auth step is a stumbling block in a 10-minute demo.

2. **Consistency:** Recipe packages (`recipes/state-store`, `recipes/pubsub`, `recipes/secrets`) are already public. Service images should match.

3. **Simplicity:** Pull secret wiring adds complexity to `bootstrap.sh`, `deploy-azure.yml`, and `app.bicep` parameters. Public packages eliminate all of it.

4. **No security loss:** The source code is already public. Container images built from public source reveal nothing additional.

### Fallback

The `imagePullSecrets` infrastructure remains in place for private forks or enterprise deployments. The `ghcrImagePullRef` param in `app.bicep` still works — just pass a non-empty value and pre-create the secret.

## Consequences

- `bootstrap.sh` pull secret logic becomes optional (cleanup in #36)
- `deploy-azure.yml` does not need a pull secret step (only needs it if packages ever go private again)
- Local `rad deploy` works with no auth ceremony
- ARM Mac developers still need `--platform linux/amd64` for AKS targets

## Related Issues

- #33 — Make GHCR packages public (P0, immediate fix)
- #34 — Fix CI workflow pull secret gap (P1, defensive)
- #35 — Local dev build-and-push script (P1, developer experience)
- #36 — Conditional pull secret logic in bootstrap.sh (P2, cleanup)

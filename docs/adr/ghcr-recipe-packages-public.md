# ADR-0002: Make GHCR Recipe Packages Public

> **Status:** ACCEPTED
> **Context:** Radius recipe OCI artifact authentication
> **Decision Drivers:** Operational simplicity, zero-friction demo setup, no sensitive data in artifacts

---

## Context

RadiusClaim publishes three Radius Bicep recipe artifacts to GitHub Container Registry (GHCR):

- `ghcr.io/wesback/radiusclaim/recipes/state-store`
- `ghcr.io/wesback/radiusclaim/recipes/pubsub`
- `ghcr.io/wesback/radiusclaim/recipes/secrets`

The Radius `applications-rp` operator fetches these OCI artifacts at deploy time using the ORAS Go library. ORAS reads registry credentials from `DOCKER_CONFIG/config.json` inside the pod. The pod runs in the `radius-system` namespace and has **no Docker credentials configured by default**.

When the packages are private, every deploy fails immediately:

```
RecipeDownloadFailed: failed to fetch repository from the path
"ghcr.io/wesback/radiusclaim/recipes/state-store": 401 unauthorized
```

### Why the obvious workarounds don't hold up

We investigated four approaches before landing here. All four were rejected.

**1. Inject a Kubernetes secret + `DOCKER_CONFIG` env var into `applications-rp`**

Works on the first install, broken on the second. `rad install kubernetes` and `rad upgrade` are Helm-managed and overwrite the pod spec on every run. The Radius Helm chart exposes no `extraEnvVars` or `extraVolumes` values for `applications-rp`, so any manual injection evaporates silently.

**2. Use the GitHub REST API to flip package visibility**

`PATCH /user/packages/container/{package_name}` returns 404 for container packages. GitHub does not expose a REST API for container package visibility — it is a web UI-only operation.

**3. Use `rad credential register`**

`rad credential` manages Azure and AWS cloud provider credentials. It has no OCI registry concept. Not applicable.

**4. Use `rad env update`**

`rad env update` has no flags for OCI registry authentication. Not applicable.

---

## Decision

**Make all three GHCR recipe packages public.**

This is a one-time action per package, performed in the GitHub web UI:

> **Packages → [package name] → Package settings → Change visibility → Public**

Direct links (for the `wesback` owner):

| Package | Settings URL |
|---------|-------------|
| `recipes/state-store` | https://github.com/users/wesback/packages/container/radiusclaim%2Frecipes%2Fstate-store/settings |
| `recipes/pubsub` | https://github.com/users/wesback/packages/container/radiusclaim%2Frecipes%2Fpubsub/settings |
| `recipes/secrets` | https://github.com/users/wesback/packages/container/radiusclaim%2Frecipes%2Fsecrets/settings |

The bootstrap script (`scripts/bootstrap.sh`) enforces this via a `require_public_recipe_access()` gate that probes each package for anonymous OCI access before deploying. If any package is still private, the script prints the direct GitHub web UI URL and exits — failing fast rather than producing a cryptic Radius error mid-deploy.

---

## Consequences

**Positive**
- Eliminates the 401 auth failure entirely — no credentials, no secrets, no pod spec surgery.
- `rad install kubernetes` and `rad upgrade` can run freely without breaking recipe access.
- Bootstrap validation catches misconfigured visibility before it causes a confusing mid-deploy failure.
- Zero ongoing credential rotation or secret management burden.

**Negative**
- The recipe packages are publicly visible on GHCR.
  - **This is acceptable.** The packages contain only Bicep templates — no credentials, connection strings, or sensitive configuration. The same templates already live in the open-source repository under `infra/radius/recipes/`. Making the compiled OCI artifacts public exposes nothing that isn't already public.

**Neutral**
- Visibility must be changed once per package via the GitHub web UI. There is no CLI or API path for this (see rejected alternatives above). The bootstrap gate and this ADR document it as a one-time prerequisite.

---

## Alternatives Considered

| Option | Why Rejected |
|--------|-------------|
| K8s secret + `DOCKER_CONFIG` env var on `applications-rp` | Overwritten on every `rad install` / `rad upgrade`; Helm chart has no hook for persistence |
| GitHub REST API (`PATCH /user/packages/container/{name}`) | Returns 404; container package visibility is not exposed via the GitHub REST API |
| `rad credential register` | Covers cloud provider credentials (Azure/AWS) only; no OCI registry support |
| `rad env update` | No OCI registry credential flags |

---

## References

- Radius recipe concepts: <https://docs.radapp.io/concepts/recipes/overview>
- ORAS Go library (used by `applications-rp`): <https://github.com/oras-project/oras-go>
- GHCR package visibility (web UI): <https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility>
- Bootstrap gate implementation: `scripts/bootstrap.sh` → `require_public_recipe_access()`
- Recipe source templates: `infra/radius/recipes/azure/`

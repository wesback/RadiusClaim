# Decision: allowAzureServices Default for PostgreSQL State Store Recipe

**By:** Graham (Platform Engineer)
**Date:** 2025-07-14
**Status:** IMPLEMENTED
**Issue:** #64

## Context

The PostgreSQL state store recipe (`infra/radius/recipes/azure/state-store.bicep`) has
`allowAzureServices bool = false` as its recipe-level default. This is secure-by-default
but makes a freshly deployed environment completely unreachable from AKS (and from the
Dapr sidecar), causing bootstrap failures.

The environment template (`azure-radius.bicep`) was not passing `allowAzureServices` at
all, meaning the recipe always fell back to its own `false` default.

## Decision

Add `param allowAzureServices bool = true` to `azure-radius.bicep` and wire it through
to the state store recipe call. The default is **true** at the environment layer for the
following reasons:

1. **Dev/demo path must work out-of-the-box.** The default end-to-end deployment
   (TEARDOWN → PREPARE_CLUSTER → BOOTSTRAP) targets a cluster without private VNet
   integration. Without `allowAzureServices=true` the database is unreachable.
2. **Two-layer defaults give operators explicit control.** The recipe default (`false`)
   remains the hardened fallback; the environment default (`true`) overrides it for
   realistic deployments while remaining overridable via `--parameters allowAzureServices=false`.
3. **Private endpoint path is unchanged.** When `usePrivateEndpoint=true` is set the
   recipe ignores `allowAzureServices`, so this change has no effect on production
   VNet-isolated deployments.

## Production Guidance

For production deployments, operators should either:
- Pass `--parameters allowAzureServices=false` and `usePrivateEndpoint=true`, or
- Deploy with a delegated-subnet VNet integration to eliminate the public firewall rule.

The `allowAzureServices=true` default is intentionally developer-friendly. The security
comment in the recipe and environment parameter description calls this out explicitly.

## Files Changed

- `infra/radius/environments/azure-radius.bicep` — added `param allowAzureServices bool = true`
  and `allowAzureServices: allowAzureServices` in the state store recipe parameters block.

# Decision: Bootstrap Live Debug — Root Causes and Fixes

**Author:** Daisy (Researcher)
**Date:** 2026-03-26
**Status:** Implemented & Verified

## Context

Ran `./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes` iteratively, diagnosing each failure and applying the minimum fix until the full RadiusClaim deployment succeeded.

## Findings & Fixes

### 1. Missing Azure identity auto-detection (bootstrap.sh)
**Symptom:** `AZURE_CLIENT_ID is required` even when Radius credential was already registered.
**Fix:** Added auto-detection logic after the credential check — when `rad credential show azure` returns a registered credential, extract `ClientID` and `TenantID` from the JSON output.
**Gotcha:** `rad credential show azure -o json` emits a preamble line to stdout; must filter with `sed -n '/^{/,$p'` before piping to `jq`.

### 2. Stale service principal secret (bootstrap.sh)
**Symptom:** `ClientSecretCredential authentication failed` during `rad deploy`.
**Fix:** When `AZURE_CLIENT_SECRET` is available and credential is already registered, always re-register to refresh the stored secret.

### 3. Missing Contributor role on SP (platform-common.sh)
**Symptom:** `AuthorizationFailed` on `Microsoft.Resources/deployments/validate/action`.
**Fix:** `ensure_radius_recipe_rbac()` now grants **both** Contributor and User Access Administrator (previously only UAA).

### 4. Bicep resource types incompatible with Radius 0.55.0 (app.bicep, azure-radius.bicep, etc.)
**Symptom:** `The resource namespace 'Radius.Core' is invalid.`
**Root cause:** Migration from `Applications.*@2023-10-01-preview` to `Radius.*@2024-01-01` was premature. Radius 0.55.0 does NOT support `Radius.Dapr/*` at all, and `Radius.Core/*` only at `@2025-08-01-preview`.
**Fix:** Reverted all bicep files to `Applications.*@2023-10-01-preview`. The BCP081 warning on these types is **not** harmless when using `Radius.*` — it means the type doesn't exist.

### 5. GHCR pull secret timing (bootstrap.sh)
**Symptom:** Pods in `ImagePullBackOff` because pull secret didn't exist when Radius created pods.
**Fix:** Moved GHCR pull secret creation to **before** `rad deploy app.bicep`, with namespace pre-creation.

### 6. GHCR token scope insufficient + ARM64 vs AMD64 mismatch
**Symptom:** Even with pull secret, pods got `403 Forbidden` from GHCR; and `no match for platform in manifest`.
**Root cause:** The `gh auth token` lacked `read:packages` scope; images built on ARM64 Mac don't run on AMD64 AKS nodes.
**Fix:** Created ACR (`radiusclaimacr`), attached to AKS, rebuilt images with `--platform linux/amd64`, pushed to ACR. AKS pulls from ACR natively via managed identity — no pull secrets needed.

## Key Technical Details

- **Radius 0.55.0 resource types:** `Applications.Core/*@2023-10-01-preview` and `Applications.Dapr/*@2023-10-01-preview` are the correct types. `Radius.Core/*@2025-08-01-preview` exists but `Radius.Dapr/*` does not exist at any version.
- **ACR + AKS integration:** `az aks update --attach-acr <name>` grants AcrPull role to the AKS kubelet identity, eliminating the need for image pull secrets.
- **Service account imagePullSecrets:** Radius `runtimes.kubernetes.pod.spec.imagePullSecrets` does NOT propagate to Kubernetes deployments in the `2023-10-01-preview` API. Workaround: patch the Kubernetes service account directly.
- **Image platform:** Always build with `--platform linux/amd64` for AKS (even on ARM Macs).

## Recommendation

- Use ACR (`radiusclaimacr.azurecr.io`) as the container registry for AKS deployments. Pass `--container-registry radiusclaimacr.azurecr.io` to bootstrap.sh.
- Do NOT migrate bicep types to `Radius.*` until Radius supports `Radius.Dapr/*` resource types.
- When `AZURE_CLIENT_SECRET` is not set, the script should not fail if credential is already registered and valid.

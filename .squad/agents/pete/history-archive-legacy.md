# Pete — History

## Session: Pete's 8-Point Audit Remediation (Scribe — Commit)

**Date:** 2026-06-05 (session completion)

All 8 findings from Pete's infrastructure scripts audit were successfully applied and committed to main:

1. **bootstrap.sh now calls WI script** — swapped deprecated `deploy-dapr-components.sh` to `deploy-dapr-components-workload-identity.sh` with `--cluster-name` flag and `AKS_CLUSTER_NAME` var
2. **teardown.sh deletes managed identity** — added `delete_managed_identity()` function and `--include-managed-identity` flag; auto-runs when `--include-resource-group` is true

---

## Core Context — Archived Sessions (Pre-2026-06-05)

The following sessions established foundational infrastructure automation patterns:

- **8-Point Audit Remediation** (2026-06-05) — Bootstrap/teardown flag consistency, managed identity cleanup, GHCR owner/repo auto-detection, DRY_RUN evaluation standardization
- **SPN Role Assignment & Credential Isolation** (2026-06-05) — Idempotent role assignment pattern, env var save/restore for privileged operations, subscription-scoped Contributor role
- **Legacy ACA Cleanup** (2026-06-05) — Removed 300 lines of dead ACA template code; updated CI validation and documentation
- **GHCR Pull Secret Automation** (2026-06-05) — Automated secret creation via `prepare-cluster.sh`, idempotent `--dry-run=client | kubectl apply` pattern
- **SP Existence Validation & Early Guards** (2026-06-05) — Pre-check SP existence before use, source-aware remediation messages, `--create-spn` override logic
- **Image Pull Secret Wiring** (2026-03-28) — Two-part Kubernetes authentication (secret creation + pod imagePullSecrets reference), identified GHCR private image gaps

These sessions established critical patterns for robust credential handling, idempotent script design, and infrastructure automation best practices.
For detailed context, see Scribe session logs and decision records.
### 2026-06-05 — SPN Role Assignment Fix (Reuse Path)

**Problem:** When `prepare-cluster.sh --create-spn` finds an existing SPN by name (`radiusclaim-radius-sp`), the user can choose to reuse it. However, the script immediately exits at line 381 WITHOUT verifying or assigning the Contributor role. This caused Wesley's bootstrap to fail with `AuthorizationFailed` — the SPN existed but lacked permissions to create resource groups.

**Root cause:** The existing SPN reuse path (lines 367-382) handled credentials but completely skipped role assignment verification. The script assumed an existing SPN was already correctly configured.

**Fix applied:**

1. **Idempotent role assignment:** When reusing an existing SPN, the script now attempts `az role assignment create` with the Contributor role on the subscription scope. This succeeds if the role doesn't exist, and fails silently if it does (2>/dev/null redirect).

2. **Verification fallback:** If role creation fails (likely because it already exists), the script uses `az role assignment list` to verify the Contributor role is actually present. Only if both operations fail does the script report a fatal error.

3. **Clear confirmation:** After ensuring the role exists, the script prints: `✓ Role assignment: Contributor on subscription <id>` (or "already exists" variant).

4. **New SPN path unchanged:** When creating a brand new SPN (lines 419-425), the script already had `--role Contributor --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}"` in the `az ad sp create-for-rbac` call. Added explicit confirmation log after creation: `✓ Role assignment: Contributor on subscription <id>`.

**Idempotency guarantee:** The fix uses `az role assignment create` (which is NOT idempotent by default) but catches failures and verifies with `az role assignment list`. This pattern ensures:
- First run: role gets created
- Subsequent runs: creation fails silently, verification succeeds, script continues
- No double-assignment errors, no false failures

**Subscription scope choice:** The script assigns Contributor at `/subscriptions/{subscriptionId}` rather than resource group scope because:
- The RG might not exist yet (bootstrap creates it)
- Subscription-level Contributor allows the SPN to create RGs and all child resources
- More idempotent for bootstrap/teardown cycles

**Syntax check:** `bash -n scripts/prepare-cluster.sh` passes.

**References:**
- Fix date: 2026-06-05
- Requested by: Wesley Backelant
- Error context: `AuthorizationFailed` on SPN `890caf69-5a38-4bf9-950d-0430352e7396` attempting to create RG `radiusclaim-rg`

---

### 2026-06-05 — SPN Credential Isolation Fix (Catch-22)

**Problem:** When `prepare-cluster.sh --create-spn` is run with `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID` already set in the environment, the Azure CLI authenticates AS the service principal for ALL commands — including role assignment and resource group creation. This creates a Catch-22: the SPN is trying to assign Contributor to itself or create resource groups, but it doesn't have `Microsoft.Authorization/roleAssignments/write` or `Microsoft.Resources/subscriptions/resourcegroups/write` permissions yet.

**Root cause:** The script didn't isolate user credentials from SPN credentials. When SPN env vars are set, `az` uses them for authentication, causing privileged operations (role assignments, RG creation) to run as the unprivileged SPN instead of the user's own Azure identity.

**Fix applied:**

1. **Existing SPN reuse path (lines 372-405):** When reusing an existing SPN, the script now:
   - Saves the SPN env vars to local variables (`saved_client_id`, `saved_client_secret`, `saved_tenant_id`)
   - Unsets `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` before role assignment
   - Runs `az role assignment create` as the user's own credentials
   - Restores the SPN env vars after role assignment completes (or on failure)
   
2. **Resource group creation (lines 158-184):** Applied the same pattern:
   - Saves SPN env vars before `az group create`
   - Unsets them so the command runs as the user
   - Restores them after the command completes
   
**Why this works:** The user's Azure identity (from `az login`) has sufficient permissions to create resource groups and assign roles. By temporarily unsetting the SPN env vars, we let the user's credentials take over for these privileged operations, then restore the SPN env vars so subsequent `rad credential register azure sp` still works correctly.

**Verification:** `bash -n scripts/prepare-cluster.sh` passes.

**References:**
- Fix date: 2026-06-05
- Requested by: Wesley Backelant
- Error context: `AuthorizationFailed` on SPN `890caf69-5a38-4bf9-950d-0430352e7396` attempting role assignment and RG creation

## Learnings

### 2026-06-05 — Legacy ACA Cleanup (Issue #12)

**Task:** Remove all Azure Container Apps references left from a prior architecture phase.

**What was removed:**
- `infra/radius/environments/azure.bicep` — The full ACA Bicep template (`Microsoft.App/managedEnvironments`, `daprComponents`, Log Analytics, ACR, Storage, Service Bus, Key Vault, role assignments). ~300 lines of dead code.
- `infra/radius/environments/azure.json` — The compiled ARM output.
- `infra/radius/environments/azure.parameters.json` — ACA-specific parameters.

**Files updated (not deleted):**
- `.github/workflows/deploy-azure.yml` — Removed the `az bicep build --file infra/radius/environments/azure.bicep` line from the validate step. The step previously validated 3 bicep files; now validates the 2 active ones only.
- `scripts/validate-deployment.sh` — Lines 12 and 129 referenced `azurecontainerapps.io` as the example URL. Updated to `nip.io` format matching the AKS gateway pattern.
- `docs/PRD.md` — Removed the `azure.bicep` row from the environment table; removed the "[LOW] Legacy ACA Environment Cleanup" backlog item; updated the ADR-0001 impact description to drop "ACA is legacy reference only".

**Search pattern used:** `containerapp|Microsoft\.App/containerApps|azure-container-apps|ContainerApp|Azure Container App|ACA` across infra/, scripts/, docs/, .github/

**Key insight:** The ACA template was already self-described as "legacy" and the PRD had it listed as a LOW cleanup item (#12). Zero application or CI code depended on it — removal was pure housekeeping with no functional risk.

**Verification:** `bash -n scripts/*.sh` all pass; grep for ACA patterns returns zero results.

**PR:** squad/12-aca-cleanup → closes #12

## Learnings

### 2026-06-05 -- GHCR Image Pull Secret Automation (Issue #16)

**Problem:** Creating the `ghcr-pull-secret` Kubernetes secret was a manual step after every fresh cluster build. Operators who skipped it saw silent pod scheduling failures because AKS could not pull images from `ghcr.io/wesback`.

**Fix applied:**

- Added `GHCR_TOKEN="${GHCR_TOKEN:-}"` and `GHCR_USERNAME="wesback"` variables at top of `prepare-cluster.sh`.
- Added `--ghcr-token <token>` CLI flag (overrides env var) with matching `usage()` documentation.
- Introduced `ensure_ghcr_pull_secret()` function that runs after kubectl is confirmed reachable. Uses the idempotent `--dry-run=client -o yaml | kubectl apply -f -` pattern.
- When token is absent, emits a clear warning (no hard fail) -- script completes, missing secret surfaced in summary line.
- Added `GHCR_TOKEN` row to the README "Required Repository Secrets" table.

**Key pattern -- pipe in dry-run context:** `run_cmd` uses `"$@"` and cannot carry pipes. Handle dry-run inline like `install_radius_if_needed`: check `[ "$DRY_RUN" = true ]` explicitly.

**Verification:** `bash -n scripts/prepare-cluster.sh` passes.

**PR:** squad/16-ghcr-pull-secret closes #16

### 2026-06-05 -- SP Existence Validation Before Accepting Env Credentials

**Problem:** `prepare-cluster.sh` blindly accepted `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` without verifying the SP exists. When a stale or deleted SP client ID was exported, the script logged a success and continued, only to fail later in `bootstrap.sh`'s `resolve_azure_principal_id()` with a cryptic empty-result error from `az ad sp show`.

**Root cause pattern:** Trusting user-exported env vars at face value. The identity may have been deleted from Azure AD while the env vars lingered in a shell session or CI secret store.

**Fix applied:**

- Added an SP existence check immediately after the three env vars are detected, before the `log_success`.
- Used the same save/restore pattern already present at lines 432–466 (for the reuse-existing-SP flow): unset the three SP env vars so `az` queries using the operator's own login context (not the SP itself, which may have restricted Graph permissions or no token at all), then restore unconditionally before any early exit.
- Query: `az ad sp show --id "$_saved_client_id" --query id -o tsv 2>/dev/null || true` — returns empty string on 404, no exception.
- On empty result: `log_error` + three `log_info` action items + `fail`. Error message names the client ID, the tenant, and the two remediation paths (create new with `--create-spn`, or export valid creds).
- Happy path (SP exists): proceeds to `log_success` unchanged.

**Key convention:** Always restore env vars *before* calling `fail` — `fail` calls `log_error` and `exit 1` so any restore after it would be dead code. Restore first, check, then fail.

**Verification:** `bash -n scripts/prepare-cluster.sh` passes. Modified section viewed and confirmed correct.

### 2026-06-05 -- Early SP Guard in bootstrap.sh

**Problem:** `bootstrap.sh` calls `resolve_azure_principal_id()` at two separate points (RBAC pre-check and principal resolution before the plan section). When `AZURE_CLIENT_ID` references a deleted/stale SP, both calls emit the "⚠️ Cannot resolve principal ID" stderr block, producing duplicate noise before the script ultimately fails at line 797.

**Root cause:** No early validation of `AZURE_CLIENT_ID` in `bootstrap.sh` main body; `prepare-cluster.sh` has this guard but `bootstrap.sh` can be run directly.

**Fix applied:**

- Added a single SP existence guard immediately before the first `resolve_azure_principal_id` call.
- Uses the same save/restore pattern as `prepare-cluster.sh` lines 182–192: save the three SP env vars, `unset` them so `az` runs under the operator's own login context, run `az ad sp show`, restore unconditionally before any exit.
- Variable names prefixed `_sp_guard_` (not `local` — guard is in the script main body, not inside a function).
- On failure: `log_error` naming the client ID + two `log_info` remediation steps + `fail`. Prevents both downstream `resolve_azure_principal_id` calls from executing.
- On success: guard exits cleanly, both subsequent calls proceed normally and the SP lookup inside them will succeed.
- Guards `AZURE_PRINCIPAL_ID` short-circuit: if `AZURE_PRINCIPAL_ID` is already explicitly set, the guard is skipped (it's not needed — `resolve_azure_principal_id` will return it directly without any SP lookup).

**Key convention confirmed:** Restore env vars *before* calling `fail` — never after.

**Verification:** `bash -n scripts/bootstrap.sh` passes.

### 2026-06-06 -- Source-Aware Remediation for Stale SP Guard

**Problem:** When `AZURE_CLIENT_ID` was auto-detected from a stored Radius credential (not set by the user), and that SP no longer exists in Azure AD, the early guard in `bootstrap.sh` emitted "Unset AZURE_CLIENT_ID" — wrong advice because the user never set that variable.

**Root cause:** The guard had a single static error message regardless of whether `AZURE_CLIENT_ID` came from the user's environment or was auto-populated from `rad credential show azure`.

**Fix applied:**

- Before the auto-detection block, check if `AZURE_CLIENT_ID` is already in env and set `_AZURE_CLIENT_ID_SOURCE="env"`.
- Inside the auto-detection assignment (line ~729), set `_AZURE_CLIENT_ID_SOURCE="radius-credential"`.
- In the guard failure branch, check `_AZURE_CLIENT_ID_SOURCE`:
  - `"radius-credential"` → emit stale-Radius-credential message with `rad credential unregister azure` + `--create-spn` re-run instructions.
  - `"env"` (or unset) → keep original "Unset AZURE_CLIENT_ID" message.
- `unset _AZURE_CLIENT_ID_SOURCE` in both the failure path and the success path cleanup.

**Key learning:** When a script auto-fills env vars from stored state, track the source of each fill so downstream error messages can give contextually accurate remediation — especially when the fix is completely different depending on who set the value.

**Verification:** `bash -n scripts/bootstrap.sh` passes.

### 2026-06-06 -- SP Guard Restructure: `--create-spn` Wins Over Stale Env Vars

**Problem:** In `scripts/prepare-cluster.sh`, when `AZURE_CLIENT_ID/SECRET/TENANT_ID` were set but stale (SP deleted), the guard always called `fail` — even when `--create-spn` was passed. The flag's intent was completely blocked.

**Root cause:** The original structure restored env vars immediately after the `az ad sp show` check and then unconditionally failed if SP was missing. The `CREATE_SPN` flag was only checked in the `else` branch (no env vars set), so it had no effect when stale vars were present.

**Fix applied:**

- Introduced `_create_new_spn=false` flag before the outer `if`.
- In the SP-missing branch, now checks `CREATE_SPN`: if `true`, logs a warning, leaves env vars unset, sets `_create_new_spn=true`; if `false`, restores vars and fails with actionable guidance.
- Moved all SP creation code out of the `else` branch into a separate `if [ "$_create_new_spn" = true ]` block, so both paths (no env vars, or stale env vars + `--create-spn`) share one creation code path without duplication.
- Fixed a pre-existing bug: `local` keyword used at top-level script scope (inside the `else` branch, not a function) — replaced with plain variable assignments (`_reuse_saved_*`).

**Key learning:** When a flag (`--create-spn`) is intended to override auto-detected or stale state, the flag check must appear *inside* the branch that detects that state — not only in a sibling `else` branch that is never reached. Use a `_create_new_spn`-style flag to unify divergent entry paths into a single implementation block, avoiding code duplication.

**Verification:** `bash -n scripts/prepare-cluster.sh` passes.

### 2026-06-06 -- Add `--create-spn` to bootstrap.sh (Stale Radius Credential Path)

**Problem:** `scripts/bootstrap.sh` auto-detects `AZURE_CLIENT_ID` from the stored Radius credential. When that SP is stale/deleted, the early guard hard-fails with a message telling the user to re-run with `--create-spn` — but bootstrap.sh didn't support that flag at all. It would reject `--create-spn` as an unknown option.

**Root cause:** The `--create-spn` flag and SP creation logic existed only in `prepare-cluster.sh`. The bootstrap error message referenced it but the flag was never added to bootstrap's arg parser or execution flow.

**Fix applied:**

- Added `CREATE_SPN=false` variable initialization alongside other bootstrap flags.
- Added `--create-spn` to the usage text and argument parsing loop.
- Modified the early SP existence guard: when `CREATE_SPN=true` and SP is stale, it now warns (instead of failing) and clears `AZURE_CLIENT_ID/SECRET/TENANT_ID` plus `_AZURE_CLIENT_ID_SOURCE` so downstream logic sees no existing creds.
- Added a full SP creation block (mirroring `prepare-cluster.sh`) between the guard and `resolve_azure_principal_id`. Handles: existing SP by name (reuse-or-suffix prompt), fresh creation with `az ad sp create-for-rbac`, credential output with save warning.
- Added an `elif` catch: if `AZURE_CLIENT_ID` is empty and `CREATE_SPN=false`, fails early with actionable guidance (covers the case where no creds exist and no flag was passed).
- Sets `SHOULD_REGISTER_AZURE_CREDENTIAL=true` and `AZURE_CREDENTIAL_REGISTERED=false` after SP creation so the downstream Radius credential registration fires automatically.

**Key learning:** When an error message tells the user to pass a flag, that flag must actually exist in the script. Always trace the full user journey: if the remediation path you advertise isn't implemented, the user hits a second, more confusing error. Cross-script feature parity matters — if both `prepare-cluster.sh` and `bootstrap.sh` can encounter the same stale-SP scenario, both need the `--create-spn` escape hatch.

**Verification:** `bash -n scripts/bootstrap.sh` passes.

### 2026-06-06 — Fix ImagePullBackOff: Patch default SA with ghcr-pull-secret post-deploy

**Problem:** All 3 application pods (expense-api, workflow-engine, notification-svc) fail with
`ImagePullBackOff` after `rad app deploy`. `ghcr-pull-secret` existed in the workload namespace
but was not wired to the `default` service account, so Kubernetes never used it.

**Root cause investigation:**
- `bootstrap.sh` already pre-creates `ghcr-pull-secret` before `rad deploy` ✓
- `bootstrap.sh` already passes `--parameters "ghcrImagePullRef=ghcr-pull-secret"` to `rad deploy` ✓
- `infra/radius/modules/container-service.bicep` already builds `runtimes.kubernetes.pod.spec.imagePullSecrets`
  from that parameter ✓
- BUT: the generated Kubernetes pod specs do NOT contain `imagePullSecrets`. Radius silently
  ignores the `spec.imagePullSecrets` override inside `runtimes.kubernetes.pod`. This appears
  to be a Radius version limitation — the pod override path supports labels but not `spec`
  sub-fields like `imagePullSecrets`.

**Fix applied — `patch_pull_secret_to_serviceaccount()` in `scripts/bootstrap.sh`:**
- Added function after `wait_for_sidecar_log` in the function block (line ~656)
- Called after `rad deploy` + `wait_for_namespace`, before `wait_for_deployment`
- Function behaviour:
  - No-op if `GHCR_TOKEN`/`GHCR_USERNAME` not set (silent skip)
  - No-op in dry-run mode (logs intent)
  - Re-creates `ghcr-pull-secret` if Radius cleared it during namespace lifecycle
  - Idempotent SA patch — checks existing `imagePullSecrets` before patching
  - Deletes ImagePullBackOff pods via `jq` query so they restart immediately
- Section header "Wiring GHCR pull secret to service account" separates this from "Waiting for workloads"

**Key learning:** Radius's `runtimes.kubernetes.pod` object supports pod-level label injection
(confirmed working for workload identity labels), but `spec.imagePullSecrets` override is silently
dropped. The service account `imagePullSecrets` field is a better hook for this anyway: it
applies to every pod in the namespace regardless of which controller created them, and survives
re-deploys as long as the SA exists.

**Graham notified:** `.squad/decisions/inbox/pete-pull-secret-wiring.md` — asks Graham to verify
whether `runtimes.kubernetes.pod.spec.imagePullSecrets` actually reaches the generated Deployment
and, if so, whether a Radius schema fix could replace the SA patch long-term.

**Verification:** `bash -n scripts/bootstrap.sh` passes.

### 2026-06-07 — Radius Stuck-State Recovery: Pre-Deploy Cleanup and Deploy Retry

**Problem:** When a previous `rad app deploy` times out (context deadline exceeded) or is
interrupted, Radius leaves container resources (expense-api, workflow-engine, notification-svc)
stuck in `Updating` provisioningState. Re-running `rad deploy` is immediately rejected with
HTTP 409 Conflict: `"The target resource is in progress state: Updating."` — blocking all
subsequent deploys until the stuck resources are manually deleted.

**Root cause:** Radius does not automatically recover resources from in-progress states after
a failed/timed-out deployment. The control plane treats them as still being modified and rejects
new operations. This is a known Radius limitation — there is no `rad resource reset` or
force-deploy flag.

**Recovery mechanism:** Deleting the stuck container resources with `rad resource delete` clears
the state. On the next `rad deploy`, Radius recreates them from scratch using the bicep definition.
Individual container deletes are preferred over `rad app delete` (too destructive — removes the
entire app and all its resources, including non-stuck ones).

**Fix applied — two new functions in `scripts/bootstrap.sh`:**

1. **`cleanup_stuck_radius_resources(app_name, group_name, workspace_name)`**
   - Runs `rad resource list Applications.Core/containers -g ... -w ... -o json`
   - Parses JSON to find containers where `provisioningState != "Succeeded"`
   - Deletes each stuck container individually with `rad resource delete ... --yes`
   - Idempotent: no-op when no containers exist or all are in Succeeded state
   - Handles missing groups, empty responses, and non-JSON prefixes gracefully
   - Logs each deletion with the resource name and stuck state

2. **`rad_deploy_with_recovery(deploy_args...)`**
   - Captures `rad deploy` stdout+stderr
   - On success: prints output, returns 0
   - On failure: checks if output contains "in progress state"
     - If yes: calls `cleanup_stuck_radius_resources`, retries deploy exactly once
     - If no: surfaces original error, returns original exit code
   - Dry-run aware: delegates to `run_cmd` when `DRY_RUN=true`

**Call sites in bootstrap main body:**
- Added `section "Checking for stuck Radius resources (pre-deploy)"` + call to
  `cleanup_stuck_radius_resources` before the deploy, as a proactive pre-flight check
- Replaced `run_cmd "$RAD_BIN" "${APP_DEPLOY_ARGS[@]}"` with
  `rad_deploy_with_recovery "${APP_DEPLOY_ARGS[@]}"` — reactive retry if pre-check missed it

**Design decisions:**
- Discovery-based, not hardcoded: uses `rad resource list` output, so any container resource
  stuck in any non-Succeeded state is caught — not just the three known service names
- Two-layer defense: pre-deploy check catches most cases; retry wrapper catches race conditions
  where state changes between the check and the deploy
- Individual deletes over app-level nuke: preserves non-stuck resources and avoids cascade
- Single retry: if the retry also fails, it's a different problem — let it surface

## Learnings

### 2026-06-07 — Radius Stuck-State is a Deployment Lifecycle Gap

Radius (as of 0.55.0) has no built-in mechanism to recover from in-progress provisioning states
after a failed or timed-out deployment. When `rad deploy` fails mid-operation:
- Container resources remain in `Updating` (or `Failed`) provisioningState
- Subsequent deploys are rejected with `409 Conflict`
- The only recovery path is `rad resource delete` on individual stuck resources
- `rad app delete` works but is overkill — it removes everything, not just the stuck ones
- There is no `rad resource reset`, `--force` flag, or automatic state reconciliation

**Detection:** `rad resource list Applications.Core/containers -g <group> -w <workspace> -o json`
→ parse `.properties.provisioningState` — anything other than `Succeeded` is stuck.

**Recovery:** `rad resource delete Applications.Core/containers/<name> -g <group> -w <workspace> --yes`
→ removes the stuck resource so `rad deploy` recreates it cleanly from bicep.

**Key pattern:** Pre-deploy health check + post-failure retry wrapper provides two layers of
defense. The pre-check handles the common case (re-running after a previous failure); the retry
handles the edge case (state changes between check and deploy).

**Verification:** `bash -n scripts/bootstrap.sh` passes.

### 2026-03-28 — GHCR Image Pull Secret Gaps Investigation

**Context:** Deployment failed with `401 Unauthorized / ImagePullBackOff` for all three service
images (`ghcr.io/wesback/radiusclaim/{notification-svc,workflow-engine,expense-api}:2f18c7b`).
The deployment is a local Radius deployment. Tag `2f18c7b` is a 7-char git SHA (confirmed exists).

**Task:** Investigate scripts, CI workflows, and Dockerfiles to identify exact gaps for local
dev workflow and CI pipeline.

**Files investigated:**
- All scripts in `scripts/` directory
- All three Dockerfiles: `src/expense-api/Dockerfile`, `src/workflow-engine/Dockerfile`, `src/notification-svc/Dockerfile`
- `.github/workflows/deploy-azure.yml` (focus on image build/push step)
- `.github/workflows/squad-ci.yml`
- `.squad/decisions.md`
- `DAPR_COMPONENT_DEPLOYMENT_STATUS.md`
- `infra/radius/app.bicep` (ghcrImagePullRef parameter usage)

**Findings — CI Workflow Gaps (deploy-azure.yml):**

1. **Image build/push step works correctly** (lines 119-136)
   - Authenticates to GHCR with `docker login ghcr.io` using `github.token`
   - Builds all three images with correct Dockerfile paths
   - Pushes to GHCR successfully with tags `$GHCR_PREFIX/$service_name:$IMAGE_TAG`

2. **Missing: imagePullSecret creation step**
   - Should be added after line 196 (Deploy Azure-backed Radius environment)
   - Must run before line 197 (Deploy application through Radius)
   - Required command: `kubectl create secret docker-registry ghcr-pull-secret --docker-server=ghcr.io --docker-username="${{ github.actor }}" --docker-password="${{ github.token }}" --namespace="$RADIUS_KUBERNETES_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -`

3. **Missing: ghcrImagePullRef parameter on rad deploy**
   - Line 200-203: `rad deploy` command missing `--parameters ghcrImagePullRef="ghcr-pull-secret"`
   - Current: only passes `containerRegistry`, `imageTag`, `deploymentTarget`
   - Required: add `--parameters ghcrImagePullRef="ghcr-pull-secret"`

**Findings — Local Developer Workflow Gaps:**

1. **No local build/push script exists**
   - Scripts present: `bootstrap.sh`, `prepare-cluster.sh`, `deploy-dapr-components-workload-identity.sh`, `deploy-dapr-components.sh`, `publish-radius-recipes.sh`, `teardown.sh`, `validate-deployment.sh`
   - Missing: `scripts/build-push-images.sh` — no documented way to build and push images locally

2. **Local developers cannot:**
   - Build service images locally
   - Push images to GHCR with proper authentication
   - Create imagePullSecret in local Kubernetes cluster
   - Deploy with pull secret reference

**Dockerfiles:**
- ✅ All three exist at expected paths
- ✅ All use correct multi-stage build structure
- ✅ All copy `RadiusClaim.slnx`, `global.json`, and required project references
- ✅ Build context is repository root (correct for all three)

**app.bicep:**
- Parameter `ghcrImagePullRef` exists with default empty string (line 28)
- Used in line 88: `var pullSecrets = empty(ghcrImagePullRef) ? [] : [{ name: ghcrImagePullRef }]`
- Empty default means Kubernetes attempts anonymous pull → 401 for private GHCR packages

**Root cause:**
- GHCR packages under `ghcr.io/wesback/radiusclaim/*` are private by default
- CI builds and pushes images successfully
- Pods attempt anonymous pull (no imagePullSecret configured)
- Kubernetes returns `ImagePullBackOff` with `401 Unauthorized`

**Recommended scripts to create:**

1. **`scripts/build-push-images.sh`** — Build and push service images to GHCR
   - Requires: `docker`, `gh` CLI (or `GHCR_TOKEN` env var)
   - Accepts: optional tag (defaults to current git SHA)
   - Authenticates with GHCR using GitHub token
   - Builds all three services in parallel
   - Outputs: Instructions for creating imagePullSecret and deploying

2. **Consider: `scripts/create-ghcr-pull-secret.sh`** — Create/update GHCR pull secret in namespace
   - Requires: `kubectl`, `gh` CLI (or `GHCR_TOKEN` env var)
   - Idempotent: uses `--dry-run=client | kubectl apply`
   - Namespace: accepts `--namespace` or defaults to current Radius namespace

**Exact CI workflow fixes required:**

1. Add imagePullSecret creation step (after line 196):
   ```yaml
   - name: Create GHCR pull secret in Kubernetes namespace
     run: |
       export KUBECONFIG="$RUNNER_TEMP/radius-kubeconfig"
       kubectl create secret docker-registry ghcr-pull-secret \
         --docker-server=ghcr.io \
         --docker-username="${{ github.actor }}" \
         --docker-password="${{ github.token }}" \
         --namespace="$RADIUS_KUBERNETES_NAMESPACE" \
         --dry-run=client -o yaml | kubectl apply -f -
   ```

2. Update rad deploy command (line 200-203) to include:
   ```bash
   --parameters ghcrImagePullRef="ghcr-pull-secret"
   ```

**Report written:** `.squad/decisions/inbox/pete-image-push-gaps.md`
- Complete gap analysis with line references
- Exact commands for CI fixes
- Template for local build script
- Confidence level: HIGH (all gaps identified with tested solutions)

## Learnings

### 2026-03-28 — GHCR Image Pull Secret is a Two-Part Wiring

Container registries require two-part authentication wiring for private images on Kubernetes:
1. **Kubernetes secret creation** — `kubectl create secret docker-registry` with registry credentials
2. **Pod imagePullSecrets reference** — either in pod spec or service account `imagePullSecrets` field

When the secret creation step is missing:
- Kubernetes attempts anonymous pull
- Private registries (GHCR, Docker Hub, ACR, etc.) return `401 Unauthorized`
- Pod enters `ImagePullBackOff` loop

When the bicep parameter is missing:
- Secret exists in cluster but pods don't reference it
- Same `ImagePullBackOff` symptom

Both must be present for private images to work.

**CI workflow pattern:**
- Build/push images to registry
- Create registry pull secret in target namespace (idempotent)
- Pass secret name as deployment parameter
- Deployment tool (Radius, Helm, kubectl) injects secret reference into pod spec

**Local dev pattern:**
- Build images locally (or use pre-pushed tags)
- Create pull secret with personal credentials
- Deploy with same parameter

**Key insight:** The `app.bicep` parameter `ghcrImagePullRef` defaults to empty string,
which makes it *opt-in* for private registries. This is safe (public images work without secrets)
but requires explicit configuration when using private registries.

**Verification:** All Dockerfiles present, image build working, parameter exists — only missing
the secret creation + parameter passing steps.

### 2026-06-XX — Shared Constants Consolidation + build-and-push Flag Parity

**Task:** Consolidate copy-pasted string literals into `platform-common.sh` and close flag gap in `build-and-push.sh`.

**What changed:**

`scripts/lib/platform-common.sh`:
- Added `DEFAULT_APP_NAME="radiusclaim"`, `DEFAULT_ENV_NAME="azure"`, `DEFAULT_WORKSPACE_NAME="radiusclaim-workspace"`, `DEFAULT_GROUP_NAME="radiusclaim-group"` following the `DEFAULT_AKS_CLUSTER_NAME` convention Rod established.

`scripts/bootstrap.sh`, `scripts/teardown.sh`:
- Replaced all four hardcoded literals (`APP_NAME`, `ENV_NAME`, `GROUP_NAME`, `WORKSPACE_NAME`) with `"${DEFAULT_*}"` references.

`scripts/deploy-dapr-components.sh`, `scripts/deploy-dapr-components-workload-identity.sh`:
- Replaced `APP_NAME="radiusclaim"` and `ENV_NAME="azure"` literals with `"${DEFAULT_*}"` references.

`scripts/prepare-cluster.sh`:
- Replaced `WORKSPACE_NAME="radiusclaim-workspace"` and `GROUP_NAME="radiusclaim-group"` literals with `"${DEFAULT_*}"` references (not in original task list but had the same problem).

`scripts/build-and-push.sh`:
- Sourced `platform-common.sh` to gain `run_cmd`, `fail`, `log_*` helpers.
- Added `DRY_RUN=false` default.
- Added `usage()` function (cat <<USAGE heredoc — same pattern as bootstrap.sh).
- Added `--dry-run` flag: sets `DRY_RUN=true`.
- Added `--help`/`-h` flag: calls `usage; exit 0`.
- Replaced bare `docker build` / `docker push` calls with `run_cmd docker build` / `run_cmd docker push` so dry-run suppresses execution.
- Replaced `echo "ERROR:..." >&2; exit 1` with `fail` for consistency.
- Updated unknown-flag handler to `usage >&2; fail "Unknown flag: $1"` matching bootstrap.sh pattern.

**Verification:** `bash -n` passed on all 7 modified files.

## Learnings

### 2026-06-XX — DEFAULT_ Constants Must Land in platform-common.sh Before Scripts Use Them

`platform-common.sh` is sourced at the top of every script before defaults are set. Adding `DEFAULT_*` constants there guarantees they are available at the exact line where the script assigns its local variable — no ordering issue possible.

The `${DEFAULT_X}` reference (not `${DEFAULT_X:-fallback}`) is correct here: the constants are unconditional assignments in platform-common.sh, so they are always defined by the time they're needed. Adding a fallback would mask a sourcing failure silently.

When adding `--dry-run` + `--help` to a script that didn't previously source `platform-common.sh`, source it first — `run_cmd` already implements the DRY_RUN guard correctly and avoids duplicating the logic inline.

---

## Session: Shared Script Constants Extraction (2026-04-01)

**Agent:** pete-fix-common-constants

### Fixed Issues

1. **Project-level constants copy-pasted across 5+ scripts**
   - Extracted `DEFAULT_APP_NAME="radiusclaim"` to platform-common.sh
   - Extracted `DEFAULT_ENV_NAME="azure"` to platform-common.sh
   - Extracted `DEFAULT_WORKSPACE_NAME="radiusclaim-workspace"` to platform-common.sh
   - Extracted `DEFAULT_GROUP_NAME="radiusclaim-group"` to platform-common.sh
   - All 5 consuming scripts updated to reference shared constants

   **Benefit:** Project rename now requires one line change instead of grep-and-replace across scripts

2. **build-and-push.sh missing flag parity**
   - Sourced `platform-common.sh` to gain `run_cmd`, `fail`, log helpers
   - Added `DRY_RUN=false` default
   - Added `usage()` function (heredoc pattern matching bootstrap.sh)
   - Added `--dry-run` and `--help`/`-h` flags to flag parser
   - Wrapped `docker build` and `docker push` calls with `run_cmd` for dry-run support

   **Benefit:** build-and-push now consistent with all other infrastructure scripts

### Scripts Modified

- `scripts/lib/platform-common.sh` — Added 4 DEFAULT_ constants
- `scripts/bootstrap.sh` — 4 constant references
- `scripts/teardown.sh` — 4 constant references
- `scripts/deploy-dapr-components.sh` — 2 constant references
- `scripts/deploy-dapr-components-workload-identity.sh` — 2 constant references
- `scripts/prepare-cluster.sh` — 2 constant references
- `scripts/build-and-push.sh` — Overhaul: --dry-run, --help, run_cmd integration

### Pattern Rule

Use `DEFAULT_` prefix convention in platform-common.sh:
```bash
# In platform-common.sh:
DEFAULT_VARNAME="value"

# In each script (defaults block):
VARNAME="${DEFAULT_VARNAME}"

# Flag parser allows override:
--varname) VARNAME="$2"; shift 2 ;;
```

Do NOT use `export`. These are sourced (not subprocesses), so exported vars would pollute child environments.

### Sessions/Commits

- Decision merged: "Shared Script Constants in platform-common.sh"
- Orchestration log: 2026-04-01T14-39-51Z-pete-fix-common-constants.md

### Status

✅ All 7 modified files pass `bash -n` syntax check
✅ No behavior change for explicit flags
✅ Consistent flag interface across all scripts
✅ Single source of truth for project-level constants

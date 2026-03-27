# Pete — History

## Project Context

**Project:** RadiusClaim — .NET reference application demonstrating portable distributed systems using Dapr (app-layer building blocks) and Radius (infrastructure abstraction).

**Stack:** .NET 9, Dapr, Radius 0.55.0, AKS, Azure (Storage, Service Bus, Key Vault), Bicep, bash scripts.

**User:** Wesley Backelant

**Team root:** `/Users/wesleyb/git/RadiusClaim`

## Key Files (Pete's Domain)

- `scripts/bootstrap.sh` — main deployment orchestration (rad credential register → rad env update → rad deploy env → rad deploy app → pull secret)
- `scripts/teardown.sh` — resource cleanup (known bug: AKS skipped then deleted anyway via resource group sweep — fix in progress)
- `scripts/prepare-cluster.sh` — pre-cluster setup (AKS, kubeconfig, Radius workspace, SPN with `--create-spn` flag)
- `scripts/deploy-dapr-components.sh` — original Dapr component deployment (SP-based, deprecated)
- `scripts/deploy-dapr-components-workload-identity.sh` — workload identity version (current canonical)

## Current Cluster State (as of joining)

- **AKS:** `radiusclaim-aks` in `radiusclaim-rg`
- **Namespace:** `azure-radiusclaim`
- **Managed identity:** `radiusclaim-workload-identity` (client ID: `061dd532-71c6-40ac-9a90-750a1a868001`)
- **OIDC + Workload Identity:** enabled on AKS
- **Federated credentials:** expense-api, workflow-engine, notification-svc
- **Dapr components:** statestore (Blob, WI), pubsub (Service Bus, WI in progress), platform-secrets (Key Vault, WI)
- **Gateway:** `http://expense.radiusclaim.9.160.144.105.nip.io`

## Known Issues on Hire

- `teardown.sh` bug: `--aks-cluster` not provided → script says "skipping AKS" but deletes it anyway via resource group sweep. Graham is fixing this (agent: graham-teardown-fix).
- pubsub Service Bus still on SAS (workload identity migration in progress via graham-servicebus-wi agent).

## Learnings

### 2026-03-27: Zero-Secret Dapr Milestone Complete (Scribe)

**Update from Scribe execution of graham-servicebus-wi spawn manifest:**

Service Bus pubsub component has been migrated from SAS connection string to Azure Workload Identity, completing the zero-secret achievement for all Dapr components. The deployment script `deploy-dapr-components-workload-identity.sh` is now the canonical version for cluster deployments and includes:

- Service Bus RBAC grant (Azure Service Bus Data Owner role)
- Workload identity component manifest generation for all 3 Dapr components
- No secret creation in workload identity mode
- Clear verification steps for operators

When the cluster is next recreated, all Dapr components will authenticate via Azure AD federated tokens — zero shared secrets in the cluster.

**Related:**
- `.squad/log/2026-03-27T08-55-00Z-servicebus-wi-complete.md` — Session completion log
- `.squad/decisions/decisions.md` — Merged: Service Bus zero-secret migration, teardown script pattern
- `.squad/orchestration-log/2026-03-27T08-55-00Z-graham-servicebus-wi.md` — Orchestration record


## Learnings

### 2026-06-05 — Full Scripts Audit

**bootstrap.sh calls the deprecated script.** Line 960 invokes `deploy-dapr-components.sh` (SP/legacy), not `deploy-dapr-components-workload-identity.sh`. The entire workload identity setup path (managed identity, federated creds, deployment label patching) is never run from bootstrap. This is the #1 integration gap.

**Managed identity orphaned by teardown.** `deploy-dapr-components-workload-identity.sh` creates `radiusclaim-workload-identity`. Teardown has no code to delete it. Resource accumulates across cycles.

**Flag naming divergence.** `--workspace-name` in bootstrap/prepare vs `--workspace` in teardown. `--group-name` exists in bootstrap/prepare but is missing from teardown entirely.

**GHCR owner/repo hardcoded in teardown.** `delete_ghcr_artifacts()` hardcodes `owner="wesback"`, `repo="radiusclaim"`. Not forkable without editing source.

**Both deploy-dapr scripts don't source lib/platform-common.sh.** They use raw echo/exit patterns — inconsistent logging, no dry-run support from the common layer.

**WI script header comment names wrong file.** Says `deploy-dapr-components.sh` not `deploy-dapr-components-workload-identity.sh`.

**README doesn't mark deploy-dapr-components.sh deprecated.** Operators won't know to use the WI version.

**DRY_RUN style inconsistency.** bootstrap.sh mixes `if "$DRY_RUN"` (command invocation) with `[ "$DRY_RUN" = true ]`. Both work; inconsistency is a maintenance hazard.

**DRY_RUN style inconsistency.** bootstrap.sh mixes `if "$DRY_RUN"` (command invocation) with `[ "$DRY_RUN" = true ]`. Both work; inconsistency is a maintenance hazard.

**publish-radius-recipes.sh auth detection unreliable.** The pre-publish GHCR credential check (`docker info | grep ghcr.io`) always fails, so the warning fires for every operator regardless of actual auth state.

---

## 2026-03-27: Full Scripts Audit → Recommended Actions (1–8)

**Critical Issues (must fix before bootstrap automation):**

1. **bootstrap.sh line 960:** Change call from `deploy-dapr-components.sh` → `deploy-dapr-components-workload-identity.sh --cluster-name $CLUSTER_NAME`
2. **teardown.sh managed identity cleanup:** Add deletion code for `radiusclaim-workload-identity` resource, gated by flag (e.g., `--aks-cluster-name`) or visible skip warning

**Secondary Issues (consistency + quality):**

3. **Flag naming:** Rename teardown `--workspace` → `--workspace-name` (keep old name as hidden alias)
4. **teardown missing flag:** Add `--group-name` parameter to match bootstrap/prepare-cluster
5. **GHCR hardcoded:** Derive owner/repo from `git remote get-url origin` in teardown's `delete_ghcr_artifacts()`, with optional flag override
6. **deploy-dapr logging:** Add `source lib/platform-common.sh` to both deploy-dapr scripts; replace all `echo "Error"` + `exit` with `fail()`, `log_info()`, `log_success()` calls
7. **WI script header:** Fix comment in `deploy-dapr-components-workload-identity.sh` to name correct filename
8. **README deprecation:** Mark `deploy-dapr-components.sh` deprecated in `scripts/README.md`; point operators to WI version

**References:**
- Audit date: 2026-03-27T09:05:00Z

---

### 2026-06-05 — GHCR Package Deletion Fix (API URL Encoding)

**Problem:** `teardown.sh` GHCR package deletion was failing with 404 for all packages. The script was attempting to delete packages like `radiusclaim/expense-api` but using the wrong API path format.

**Root cause:** GitHub Container Registry API requires forward slashes in package names to be URL-encoded as `%2F`. The script was only encoding spaces (`%20`) but not slashes, so:
- Wrong: `/user/packages/container/radiusclaim/expense-api` (treats "radiusclaim" as package, "expense-api" as invalid path)
- Correct: `/user/packages/container/radiusclaim%2Fexpense-api` (treats full string as one package name)

**Fix applied:** Changed encoding from `${full_name// /%20}` to `${full_name//\//%2F}` to properly URL-encode all forward slashes in the package name.

**Package naming convention:** GHCR uses the full image path as the package name. For images pushed as `ghcr.io/wesback/radiusclaim/expense-api:latest`, the package name in the API is `radiusclaim/expense-api` (with slashes), and these slashes MUST be URL-encoded in API paths.

**Verification:** `bash -n scripts/teardown.sh` passes with no syntax errors.

**References:**
- GitHub API docs: https://docs.github.com/en/rest/packages
- Fix date: 2026-06-05
- Audit requested by: Wesley Backelant
- Scribe orchestration: `.squad/orchestration-log/2026-03-27T09-05-00Z-pete-scripts-audit.md`


## Learnings

### 2026-06-05 — GHCR Token Scope Error Handling

**Problem:** `teardown.sh` GHCR deletion now correctly finds packages (URL encoding fix), but fails with 403 when `gh` token lacks `delete:packages` and `read:packages` scopes. The error message was misleading — "may not exist or requires manual removal via GitHub UI" — when the real issue was missing token scopes.

**Fix applied:**

1. **Pre-flight scope check:** Added `gh auth status --hostname github.com` parsing to detect missing `delete:packages` scope BEFORE attempting any deletions. If scope is missing, displays clear error message with exact fix command and exits early with `return 1`.

2. **Per-deletion error parsing:** Changed from `2>/dev/null` silent failure to capturing `gh api` stderr output and parsing JSON response for HTTP status codes:
   - `403` → Clear auth error with recovery instructions: "✗ GHCR deletion requires additional token scopes / ℹ Run: gh auth refresh -s delete:packages,read:packages / ℹ Then re-run teardown with --include-ghcr-artifacts". Returns 1 immediately (no point retrying remaining packages).
   - `404` → Informational message: "Package not found (already deleted or never existed)" — skip silently.
   - Other errors → Generic warning with actual error output.

3. **Early exit on 403:** When a 403 is detected during deletion, the function returns immediately instead of attempting remaining packages. All packages use the same token, so they'll all fail with the same error.

**User experience:** Operators now get clear, actionable guidance when token scopes are insufficient, with the exact command to fix it (`gh auth refresh -s delete:packages,read:packages`).

**Verification:** `bash -n scripts/teardown.sh` passes with no syntax errors.

**References:**
- Fix date: 2026-06-05
- Requested by: Wesley Backelant
- Related: GHCR URL encoding fix (same session)

---

### 2026-06-05 — Audit Fixes Applied (Fixes 1–8)

All 8 audit findings from the 2026-06-05 audit were fixed in a single session.

**Fix 1 (bootstrap → WI script):** Added `AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-radiusclaim-aks}"` default and `--cluster-name` arg to bootstrap.sh. Changed actionable_file check and run_cmd call to use `deploy-dapr-components-workload-identity.sh` with `--cluster-name "$AKS_CLUSTER_NAME"`. bootstrap.sh previously had no AKS_CLUSTER_NAME variable — the WI script defaults to `radiusclaim-aks`, so the new default matches.

**Fix 2 (managed identity teardown):** Added `MI_NAME="radiusclaim-workload-identity"`, `INCLUDE_MANAGED_IDENTITY=false`, `delete_managed_identity()` function, and `--include-managed-identity` flag to teardown.sh. Design decision: auto-runs when `--include-resource-group` is true (RG deletion removes it anyway, but explicit messaging is better). Also opt-in standalone via `--include-managed-identity`.

**Fix 3 (flag naming):** Added `--workspace-name` as primary, kept `--workspace` as deprecated alias with `log_warning`. Added `--group-name` flag (previously `GROUP_NAME` was hardcoded with no override).

**Fix 4 (deprecation banner):** Added DEPRECATED comment block and `log_warning` call at top of `deploy-dapr-components.sh`. Added `> ⚠️ **Deprecated:**` notice to `scripts/README.md` section for that script.

**Fix 5 (GHCR owner/repo from git remote):** Rewrote `delete_ghcr_artifacts()` in teardown.sh to derive owner/repo from `git remote.origin.url` using the same regex as bootstrap.sh's `derive_default_container_registry()`. Fallback to hardcoded `wesback`/`radiusclaim` with a log_warning. Added `--ghcr-owner` and `--ghcr-repo` override flags (stored as `GHCR_OWNER_OVERRIDE` / `GHCR_REPO_OVERRIDE` to avoid `set -u` conflicts).

**Fix 6 (source platform-common.sh):** Added `SCRIPT_DIR` + `source "${SCRIPT_DIR}/lib/platform-common.sh"` to both deploy-dapr scripts. Replaced egregious `echo "Error: ..."` + exits with `log_error` calls in both. WI script header comment now names the correct file (`deploy-dapr-components-workload-identity.sh`).

**Fix 7 (dead GHCR auth detection):** Replaced the double-broken check (`docker-credential-$()` command substitution in function name + `docker info | grep ghcr.io` fallback) with a clean two-step: query credential store name from `docker info`, then call `docker-credential-<store> list | grep ghcr.io`. Shows warning only when auth is actually missing.

**Fix 8 (DRY_RUN standardization):** Used `sed` to replace all `if "$DRY_RUN"; then` → `if [ "$DRY_RUN" = true ]; then` and `if ! "$DRY_RUN"; then` → `if [ "$DRY_RUN" != true ]; then` across bootstrap.sh. 11 occurrences fixed. WI script already used `[[ "$DRY_RUN" == "true" ]]` — consistent string comparison, not command invocation.

**Syntax check:** All 5 scripts passed `bash -n` after changes.

## Session: Pete's 8-Point Audit Remediation (Scribe — Commit)

**Date:** 2026-06-05 (session completion)

All 8 findings from Pete's infrastructure scripts audit were successfully applied and committed to main:

1. **bootstrap.sh now calls WI script** — swapped deprecated `deploy-dapr-components.sh` to `deploy-dapr-components-workload-identity.sh` with `--cluster-name` flag and `AKS_CLUSTER_NAME` var
2. **teardown.sh deletes managed identity** — added `delete_managed_identity()` function and `--include-managed-identity` flag; auto-runs when `--include-resource-group` is true
3. **Flag consistency** — teardown `--workspace-name` is now primary; `--workspace` deprecated with warning; `--group-name` added
4. **deploy-dapr-components.sh deprecated** — DEPRECATED header comment and `log_warning` in script; `⚠️ Deprecated:` blockquote added to README
5. **GHCR owner/repo no longer hardcoded** — teardown now derives from `git remote.origin.url` with fallback to hardcoded values; `--ghcr-owner`/`--ghcr-repo` override flags added
6. **platform-common.sh sourced in both deploy-dapr scripts** — consistent logging and dry-run support; replaced raw `echo "Error"` with `log_error` calls
7. **GHCR auth detection fixed** — `publish-radius-recipes.sh` now uses `docker-credential-<store> list | grep ghcr.io` instead of unreliable `docker info` grep
8. **DRY_RUN evaluation consistent** — bootstrap.sh: all 11 `if "$DRY_RUN"` instances replaced with `if [ "$DRY_RUN" = true ]`

**Commit:** `0fe8322` — "fix(scripts): Pete's 8-point audit remediation"

**Status:** ✅ All scripts pass `bash -n` syntax check. Ready for bootstrap automation.

---

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

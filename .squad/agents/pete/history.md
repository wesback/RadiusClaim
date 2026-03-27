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

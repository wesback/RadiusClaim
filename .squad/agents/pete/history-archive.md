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



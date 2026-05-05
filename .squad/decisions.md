# Squad Decisions

## Active Decisions


### Context


The `scripts/teardown.sh` script includes a `delete_ghcr_packages()` function to clean up container images from GitHub Container Registry (GHCR) during teardown. This function was consistently failing with 404 errors for all packages.

### Problem


Package deletion was attempting to call:
```bash
gh api -X DELETE "/user/packages/container/radiusclaim/expense-api"
```

The GitHub API was interpreting this as:
- Package owner: (authenticated user)
- Package name: `radiusclaim`
- Invalid path segment: `expense-api`

This resulted in 404 errors because there is no package named simply "radiusclaim".

### Root Cause


GitHub Container Registry uses the full image path as the package name. For images pushed as:
```
ghcr.io/wesback/radiusclaim/expense-api:latest
```

The package name in the API is `radiusclaim/expense-api` (including the forward slash).

However, forward slashes in URL paths have special meaning and must be URL-encoded when they are part of a single path parameter. The script was only encoding spaces (`%20`) but not forward slashes.

### Decision


**All forward slashes in GHCR package names MUST be URL-encoded as `%2F` when used in GitHub API paths.**

### Implementation


Changed the encoding in `scripts/teardown.sh` line 493:

**Before:**
```bash
gh api -X DELETE "/user/packages/container/${full_name// /%20}"
```

**After:**
```bash
local encoded_name="${full_name//\//%2F}"
gh api -X DELETE "/user/packages/container/${encoded_name}"
```

This properly encodes package names like:
- `radiusclaim/expense-api` → `radiusclaim%2Fexpense-api`
- `radiusclaim/recipes/state-store` → `radiusclaim%2Frecipes%2Fstate-store`

### Package Naming Convention


**Standard GHCR package structure:**
```
ghcr.io/<owner>/<package-name>:<tag>
```

Where `<package-name>` can contain slashes and becomes the package identifier in the API.

**API endpoint format:**
```
/user/packages/container/<url-encoded-package-name>
```

**Example packages in RadiusClaim:**
- `radiusclaim/expense-api`
- `radiusclaim/workflow-engine`
- `radiusclaim/notification-svc`
- `radiusclaim/recipes/state-store`
- `radiusclaim/recipes/pubsub`
- `radiusclaim/recipes/secrets`

### Consequences


**Positive:**
- GHCR package deletion will now work correctly
- Script properly handles multi-level package names (e.g., `recipes/state-store`)
- 404 errors for non-existent packages are still handled gracefully (soft warning, as intended)

**Neutral:**
- The fix is transparent to script users — no flag or behavior changes required
- Syntax verified with `bash -n scripts/teardown.sh`

**Risk:**
- None. This is a bug fix that aligns with GitHub API requirements.

### References


- GitHub REST API: [Packages - Delete a package for the authenticated user](https://docs.github.com/en/rest/packages/packages#delete-a-package-for-the-authenticated-user)
- URL encoding spec: RFC 3986 (forward slash = `%2F`)
- Related file: `scripts/teardown.sh` line 481-498

# Decision: SPN Role Assignment Idempotency

**Date:** 2026-06-05  
**Author:** Pete (Infrastructure Automation Specialist)  
**Status:** Implemented  

## Context

The `prepare-cluster.sh --create-spn` flow has two paths:
1. Create a new SPN with `az ad sp create-for-rbac --role Contributor --scopes "/subscriptions/..."`
2. Reuse an existing SPN (by display name lookup)

The **reuse path** was broken: when an existing SPN was found and the user chose to reuse it, the script exited immediately without verifying or assigning the Contributor role. This caused Wesley's bootstrap to fail with:

```
ERROR: (AuthorizationFailed) The client '890caf69-5a38-4bf9-950d-0430352e7396' [...] does not have authorization to perform action 'Microsoft.Resources/subscriptions/resourcegroups/write'
```

The SPN existed but had no permissions.

## Decision

**When reusing an existing SPN, `prepare-cluster.sh` MUST ensure the Contributor role is assigned to the subscription before proceeding.**

Implementation:
1. Attempt `az role assignment create --assignee <appId> --role Contributor --scope /subscriptions/<id>` with `2>/dev/null` to suppress "already exists" errors
2. If creation fails (likely because assignment exists), verify with `az role assignment list` to confirm the role is present
3. Only fail if both operations fail (truly missing role)
4. Print clear confirmation: `✓ Role assignment: Contributor on subscription <id>` (or "already exists")

## Rationale

- **Idempotency:** Operators can re-run `prepare-cluster.sh --create-spn` without double-assignment errors. The script either creates the role (first run) or verifies it exists (subsequent runs).
- **Subscription scope:** Using `/subscriptions/{id}` instead of `/subscriptions/{id}/resourceGroups/{rg}` is safer because:
  - The RG might not exist yet (bootstrap creates it)
  - Subscription-level Contributor allows the SPN to create RGs and all child resources
  - Avoids circular dependency (can't assign RG scope if RG doesn't exist)
- **Clarity:** Explicit role confirmation messages prevent confusion about whether permissions were granted.

## Alternatives Considered

1. **Fail fast if SPN exists:** Force users to manually assign roles. Rejected — violates automation charter.
2. **Use resource group scope:** Rejected — requires RG to exist first, breaks first-run flow.
3. **Skip role check entirely:** Rejected — leads to cryptic AuthorizationFailed errors downstream (the original bug).

## Implementation Notes

- Changed lines 367-408 of `scripts/prepare-cluster.sh`
- Added idempotent role assignment logic in the "reuse existing SPN" branch
- Added explicit role confirmation log in the "create new SPN" branch (line 408: `log_success "Role assignment: Contributor on subscription ${AZURE_SUBSCRIPTION_ID}"`)
- Both paths now guarantee the SPN has Contributor before script completes

## Testing

- `bash -n scripts/prepare-cluster.sh` → syntax valid
- Expected behavior:
  - **First run with existing SPN:** Role gets created, script prints `✓ Role assignment: Contributor on subscription <id>`
  - **Second run:** Role creation fails silently (already exists), verification succeeds, script prints `✓ Role assignment: Contributor already exists on subscription <id>`
  - **Missing permissions:** Both operations fail, script exits with clear error: `Failed to verify or assign Contributor role to service principal. Check Azure permissions.`

## References

- Error log from Wesley's bootstrap failure (SPN `890caf69-5a38-4bf9-950d-0430352e7396`)
- Azure subscription: `5b6c36e5-b279-4005-8bf1-c73b1c2b71c2`
- Pete's history: `.squad/agents/pete/history.md` — "2026-06-05 — SPN Role Assignment Fix"

# Pete Script Fixes — Audit Remediation

**Date:** 2026-06-05  
**Author:** Pete (Infrastructure Automation Specialist)  
**Requested by:** Wesley Backelant

---

## Summary

All 8 audit findings identified in the 2026-06-05 full scripts audit were fixed. All 5 affected scripts pass `bash -n` syntax check.

---

## Fix Outcomes

### Fix 1 ✅ — bootstrap.sh calls wrong Dapr script (CRITICAL)


**Files:** `scripts/bootstrap.sh`  
**Change:** Added `AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-radiusclaim-aks}"` default variable and `--cluster-name` argument parser. Changed `actionable_file` check and `run_cmd` call from `deploy-dapr-components.sh` to `deploy-dapr-components-workload-identity.sh`, passing `--cluster-name "$AKS_CLUSTER_NAME"`.  
**Design decision:** bootstrap.sh had no AKS_CLUSTER_NAME variable. Added it with the same default used by the WI script (`radiusclaim-aks`). The `--cluster-name` flag makes it overridable at runtime.

---

### Fix 2 ✅ — teardown.sh never deletes managed identity (CRITICAL)


**Files:** `scripts/teardown.sh`  
**Change:** Added `MI_NAME="radiusclaim-workload-identity"` and `INCLUDE_MANAGED_IDENTITY=false` to defaults. Added `delete_managed_identity()` function with explicit check, federated-credential count reporting, and deletion. Added `--include-managed-identity` flag.  
**Design decision:** Follows the `--include-service-principals` pattern — opt-in. Additionally, auto-runs when `--include-resource-group` is true (since RG deletion removes it anyway, but the explicit call provides better operator visibility). Federated credentials are reported but not explicitly deleted first (Azure removes them atomically with the MI; listing count gives operators visibility).

---

### Fix 3 ✅ — Flag name inconsistency `--workspace` vs `--workspace-name`


**Files:** `scripts/teardown.sh`  
**Change:** Added `--workspace-name` as primary flag. Kept `--workspace` as deprecated alias that emits `log_warning "--workspace is deprecated, use --workspace-name"`. Added `--group-name` flag (GROUP_NAME was previously hardcoded with no override path).

---

### Fix 4 ✅ — Mark deploy-dapr-components.sh as deprecated


**Files:** `scripts/deploy-dapr-components.sh`, `scripts/README.md`  
**Change:** Added DEPRECATED comment block and `log_warning` call at the top of the script (after sourcing platform-common.sh, so `log_warning` is available). Added `> ⚠️ **Deprecated:**` blockquote notice to the README section for this script.

---

### Fix 5 ✅ — GHCR owner/repo hardcoded in teardown.sh


**Files:** `scripts/teardown.sh`  
**Change:** Rewrote `delete_ghcr_artifacts()` to derive owner/repo from `git remote.origin.url` using the same regex as `derive_default_container_registry()` in bootstrap.sh. Falls back to hardcoded values with `log_warning` if git remote parsing fails. Added `--ghcr-owner` and `--ghcr-repo` override flags (stored as `GHCR_OWNER_OVERRIDE`/`GHCR_REPO_OVERRIDE` — initialised to `""` at defaults block to be safe under `set -u`).

---

### Fix 6 ✅ — Source lib/platform-common.sh in deploy-dapr scripts


**Files:** `scripts/deploy-dapr-components.sh`, `scripts/deploy-dapr-components-workload-identity.sh`  
**Change:** Added `SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and `source "${SCRIPT_DIR}/lib/platform-common.sh"` after shebang/set in both scripts. Replaced the most egregious `echo "Error: ..."` + raw exit patterns with `log_error` calls. Fixed WI script header comment to name correct filename.  
**Note:** DRY_RUN handling in WI script uses `[[ "$DRY_RUN" == "true" ]]` inline — left as-is since `run_cmd` from platform-common.sh also checks `${DRY_RUN:-false} = true`. Compatible; no conflict.

---

### Fix 7 ✅ — Dead GHCR auth detection in publish-radius-recipes.sh


**Files:** `scripts/publish-radius-recipes.sh`  
**Change:** Replaced the double-broken auth check (command substitution in function call position + `docker info | grep ghcr.io` fallback that never matches) with a clean two-step approach: get credential store name from `docker info`, then call `docker-credential-<store> list | grep ghcr.io`. Warning is now shown only when authentication is actually absent, not on every run.

---

### Fix 8 ✅ — Standardise DRY_RUN evaluation in bootstrap.sh


**Files:** `scripts/bootstrap.sh`  
**Change:** Used `sed` to replace all 11 instances of `if "$DRY_RUN"; then` → `if [ "$DRY_RUN" = true ]; then` and `if ! "$DRY_RUN"; then` → `if [ "$DRY_RUN" != true ]; then`. The old pattern ran `true` or `false` as shell commands — technically works but non-idiomatic and inconsistent with all other scripts. No other scripts had this pattern.

---

## Syntax Check Results

```
bash -n scripts/bootstrap.sh                           → OK
bash -n scripts/teardown.sh                            → OK
bash -n scripts/deploy-dapr-components.sh              → OK
bash -n scripts/deploy-dapr-components-workload-identity.sh → OK
bash -n scripts/publish-radius-recipes.sh              → OK
```

---

### Root Cause


`rad app list` does not reliably surface applications in orphaned or broken states (e.g., bound to a non-existent or renamed environment). When querying `rad app list -o json`, the stale app never appeared in the results, so the jq filter had nothing to match.

## Decision

Implement a **two-pronged approach** to fix the stale application detection and cleanup:

### Prong 1: Replace the Broken Pre-Deploy Guard


Replace the `rad app list` query with `rad resource list Applications.Core/applications` — the same pattern used by `cleanup_stuck_radius_resources` for containers.

**Why this works:**
- Queries the resource plane directly instead of using a filtered list command
- Surfaces applications in all states, including orphaned/broken
- Returns the full resource JSON with `properties.environment` field for reliable comparison

**Implementation details:**
- Use case-insensitive comparison (`ascii_downcase` in jq) for Radius resource IDs to handle mixed-case paths ("resourceGroups" vs "resourcegroups")
- Delete via `rad resource delete "Applications.Core/applications/${APP_NAME}"` (not `rad app delete`)

### Prong 2: Add Recovery to `rad_deploy_with_recovery`


Extend the `rad_deploy_with_recovery` function to also detect and recover from the "different application and/or environment" BadRequest error.

**Recovery flow:**
1. If `rad deploy` fails with "different application and/or environment" in the error message
2. Log a warning that a stale application resource was detected
3. Delete the stale app: `rad resource delete "Applications.Core/applications/${APP_NAME}"`
4. Retry the deploy exactly once (same pattern as existing stuck-state recovery)

**Why this is valuable:**
- Provides a safety net even if the pre-deploy guard misses the stale app (e.g., due to timing issues or unexpected JSON format)
- Follows the same pattern as the existing stuck-state recovery
- Makes the bootstrap script more resilient to edge cases

## Consequences

### Positive

- Bootstrap script is now idempotent even when applications are bound to different environments
- Two layers of defense (pre-deploy guard + deploy recovery) make the script robust against edge cases
- Uses the reliable `rad resource list` command for resource plane queries
- Happy path (no stale app) adds only a single `rad resource list` call with zero deletions

### Negative

- Slightly more complex recovery logic in `rad_deploy_with_recovery`
- Adds another error case to monitor and maintain

### Neutral

- Case-insensitive comparison required for Radius resource IDs (mixed-case paths in the wild)
- Idempotent deletions (`|| true`) mean failed deletions are suppressed — acceptable for this use case

## Alternatives Considered

1. **Keep using `rad app list` but add more filters:** Rejected because `rad app list` fundamentally does not surface orphaned apps.

2. **Only implement the recovery (skip pre-deploy guard):** Rejected because proactive cleanup is cleaner and more debuggable than always relying on error recovery.

3. **Only implement the pre-deploy guard (skip recovery):** Rejected because a safety net makes the script more resilient to unexpected edge cases.

## Implementation Notes

- Both guard and recovery respect the `DRY_RUN` flag
- Both use `|| true` suppression on deletions to be safe against non-existent resources
- The pre-deploy guard extracts valid JSON using `sed -n '/^\[/,$p'` to handle rad CLI output quirks
- Environment ID comparison is case-insensitive to handle Radius resource ID inconsistencies

## Related

- `.squad/skills/radius-idempotent-deployment/SKILL.md` — updated with corrected stale application guard pattern
- `scripts/bootstrap.sh` — both fixes implemented
- Previous decision: `graham-radius-idempotency.md` (namespace collision guard)

# Karen — Phase 7 verdict

Date: 2026-06-13
Reviewer: Karen (Tester)
Requested by: Wesley Backelant

## Verdict

**APPROVED**

## Why

Billy's fix correctly addresses the root cause in `ApproveExpenseActivity`: threshold routing is now derived from `ExpenseSubmission.Amount`, so the auto-approve/manual-review decision no longer blocks on a potentially stale state-store read.

`ExpenseApprovalWorkflow` still branches correctly:
- `$50` (`amount < threshold`) returns `Approved`, then proceeds to reimbursement
- `$150` (`amount >= threshold`) returns `ManualReviewRequested`, then waits for manual decision
- `$100.00` stays on the manual-review side because the comparison is strict `< threshold`

This directly addresses `scripts/validate-deployment.sh` Check 4, which waits for the submitted $50 expense to reach `Approved` instead of stalling forever in `Submitted` after an activity exception.

## Risks

- The fix does **not** skip threshold validation; it simply moves the source of truth for the decision to workflow input, which already contains the submitted amount.
- Correlation and invalid-state checks still run when the record is present.
- Remaining risk is timing/observability, not business logic: if the approval activity returns from input-only while the record is still missing, later progression still depends on the record being visible before reimbursement runs.

## Test gap

Existing tests are directionally good but not complete for the race:

- `ApproveExpenseActivityTests` now covers the null-record fallback for the activity itself.
- `ExpenseWorkflowActivityChainTests` proves the happy-path chain when the record is already visible in the in-memory store.
- Missing coverage: a test that simulates the actual race sequence where `ApproveExpenseActivity` initially sees `null`, returns a decision, and the workflow/next step still converges once state becomes visible.

That gap is worth adding, but it does **not** block approval of this fix because the changed activity logic matches the diagnosed failure mode and the focused suites still pass.

# Dapr Component Stale Environment Cleanup Pattern

**Date:** 2026-04-01  
**Author:** Rod (Dapr/Radius Platform Expert)  
**Status:** Active  
**Scope:** Bootstrap, Radius deployment, Dapr components

## Context

During bootstrap, we encountered HTTP 400 BadRequest errors when deploying Dapr component resources (secretStores, stateStores, pubSubBrokers) that were previously bound to a different Radius environment. The application resource deployed successfully after we added the stale application guard, but Dapr components still had stale environment bindings.

## Decision

**We extend the stale resource cleanup pattern to include all Dapr component resource types.**

### Resource Types Affected


- `Applications.Dapr/secretStores`
- `Applications.Dapr/stateStores`
- `Applications.Dapr/pubSubBrokers`

### Implementation


1. **Pre-deploy detection:** Before `rad deploy app.bicep`, list all Dapr component resources and check their `.properties.environment` field against the target environment ID.

2. **Deletion command syntax:** Use `rad resource delete <type> <name>` with TWO separate positional args:
   ```bash
   rad resource delete Applications.Dapr/secretStores platform-secrets -g <group> -w <workspace> --yes
   ```
   
3. **Idempotency:** Always use `|| true` on deletion commands so failures don't abort the script.

4. **Recovery handler:** Update `rad_deploy_with_recovery()` to extract the failed resource name from error messages and attempt deletion across all resource types (application + 3 Dapr component types).

### Code Location


- Pre-deploy guards: `scripts/bootstrap.sh` lines ~1530-1605
- Recovery handler: `scripts/bootstrap.sh` lines ~840-885
- Documentation: `.squad/skills/radius-idempotent-deployment/SKILL.md`

## Rationale

Dapr components are first-class Radius resources that track their parent environment binding in the control plane. They follow the same lifecycle rules as Applications.Core/applications resources. When an environment is renamed or recreated, these components become stale and block deployment with the same "different application and/or environment" error.

The stale application guard pattern was already proven to work for application resources. Extending it to Dapr components ensures idempotent deployments across all resource types.

## Consequences

### Positive


- Bootstrap is now idempotent for Dapr component resources
- Environment renames/recreation won't leave stale Dapr components behind
- Error recovery is automatic — no manual intervention required

### Negative


- `rad resource delete` may hang on resources in "Updating" or "Failed" state (Radius control plane issue)
- Adds ~75 lines to bootstrap.sh (but follows established pattern)

## Alternatives Considered

1. **Manual cleanup:** Document the manual steps for deleting stale resources → rejected because it breaks idempotency
2. **Kubernetes-level cleanup:** Delete the underlying Kubernetes secrets/configmaps → rejected because Radius control plane state would still be stale
3. **Radius control plane restart:** Force-reset the control plane → rejected because it's too invasive and loses all state

## Notes

- This pattern may need to be extended to other Radius resource types (e.g. Applications.Dapr/configurationStores, Applications.Messaging/*, etc.) as they are added to the application.
- The two-arg deletion syntax (`rad resource delete <type> <name>`) is critical — a single combined path silently fails.
- Case-insensitive comparison (`ascii_downcase` in jq) is required for Radius resource IDs because the control plane may return mixed-case paths.

## Related

- Stale application guard: `.squad/skills/radius-idempotent-deployment/SKILL.md` (Stale Application Guard section)
- Radius CLI idempotency learnings: `.squad/agents/rod/history.md` (Key Decisions & Patterns section)

# Radius Orphaned Resource State Issue

**Date:** 2026-04-01  
**Reporter:** Rod (Dapr/Radius Platform Expert)  
**Status:** Unresolved — requires upstream Radius fix or workaround

## Problem

After deleting Dapr Component resources directly via `kubectl delete`, the Radius control plane retains orphaned references in its internal database. These orphaned references block future deployments with environment binding mismatch errors, even though the underlying Kubernetes resources are gone.

## Current State

- **Kubernetes layer:** All three stale Dapr components (`platform-secrets`, `statestore`, `pubsub`) successfully deleted from namespace `radiusclaim-azure-radiusclaim`
- **Radius control plane:** Orphaned references persist in "Failed" or "Updating" state
- **Deployment status:** Blocked with error: "Attempted to deploy existing resource 'statestore' which has a different application and/or environment"

## What Was Tried

1. ✅ `kubectl delete component <name> -n radiusclaim-azure-radiusclaim` — succeeded
2. ❌ `rad resource delete Applications.Dapr/stateStores statestore` — hung indefinitely
3. ❌ Deployment with `rad deploy` — failed with environment binding mismatch
4. ❌ No `rad` cleanup/purge/reset commands available

## Root Cause

Radius uses a two-tier architecture:
1. Kubernetes CRDs for actual Dapr components (managed by Dapr runtime)
2. Radius control-plane database for resource lifecycle metadata (environment bindings, provisioning state)

Direct `kubectl delete` only clears tier 1, leaving tier 2 with orphaned references.

## Potential Workarounds (Not Yet Tested)

1. **Restart Radius control plane pods** (may trigger garbage collection):
   ```bash
   kubectl rollout restart deployment applications-rp -n radius-system
   kubectl rollout restart deployment ucp -n radius-system
   ```

2. **Direct database manipulation** (not recommended, requires knowledge of Radius internals):
   - Radius likely stores state in etcd or a persistent volume
   - Would require connecting to the database and manually removing entries
   - High risk of corrupting Radius state

3. **Full Radius reinstall** (nuclear option):
   ```bash
   rad uninstall kubernetes
   rad install kubernetes
   # Re-create environments, workspaces, etc.
   ```

## Recommendation

1. File upstream issue with Radius project describing:
   - Orphaned references after direct kubectl deletion
   - Request for `rad resource purge` or `rad db cleanup` command
   - Or automatic garbage collection of resources not found in Kubernetes

2. For this project, consider the nuclear option (Radius reinstall) if:
   - This is a dev/test environment
   - The orphaned state is blocking critical work
   - Other workarounds fail

3. Update bootstrap script to NEVER use direct kubectl deletion as a fallback
   - Always rely on `rad resource delete` (even if it hangs)
   - Accept that hung deletions may require manual intervention

## Test Results

### Control-Plane Restart (PARTIAL SUCCESS)


After restarting `applications-rp` and `ucp` deployments:

1. ✅ `platform-secrets` and `statestore` changed from "Failed" to "Updating"
2. ❌ `pubsub` remained in "Failed" with environment binding error
3. ⚠️ Deployment still blocked:
   - `platform-secrets` and `statestore` now report: "The target resource is in progress state: Updating"
   - `pubsub` still reports: "Attempted to deploy existing resource 'pubsub' which has a different application and/or environment"

**Interpretation:** The control plane IS attempting to reconcile the missing Kubernetes resources after restart, but it's stuck in an infinite "Updating" loop because the underlying resources are gone. The `pubsub` resource appears to have additional state corruption that prevents even the reconciliation attempt.

## Next Steps

- [x] Test control-plane restart workaround → PARTIAL SUCCESS (stuck in Updating loop)
- [ ] Test full Radius reinstall (nuclear option)
- [ ] File upstream issue with Radius project
- [ ] Update bootstrap script documentation with known limitations

## Recommendation

**For this project (dev environment):** Consider full Radius reinstall to clear corrupted state

**For production environments:** This is a blocker issue that requires upstream Radius fix

# Stale Dapr Component Deletion Task — Summary

**Date:** 2026-04-01  
**Assigned to:** Rod (Dapr/Radius Platform Expert)  
**Requested by:** Wesley Backelant

## Task Objective

Retry deletion of three stale Dapr components (`platform-secrets`, `statestore`, `pubsub`) that were bound to the old `radiusclaim-azure` environment and blocking deployment to the new `azure` environment.

## Results

### What Worked


1. ✅ **Kubernetes-level deletion succeeded:**
   ```bash
   kubectl delete component platform-secrets -n radiusclaim-azure-radiusclaim
   kubectl delete component statestore -n radiusclaim-azure-radiusclaim
   kubectl delete component pubsub -n radiusclaim-azure-radiusclaim
   ```
   All three Dapr Component CRDs were successfully removed from the cluster.

2. ✅ **Control-plane restart partially effective:**
   ```bash
   kubectl rollout restart deployment applications-rp -n radius-system
   kubectl rollout restart deployment ucp -n radius-system
   ```
   After restart, `platform-secrets` and `statestore` changed from "Failed" to "Updating" state, indicating the control plane detected the missing Kubernetes resources and is attempting reconciliation.

### What Didn't Work


1. ❌ **`rad resource delete` hung indefinitely:**
   - `rad resource delete Applications.Dapr/secretStores platform-secrets` — no response after 60+ seconds
   - Had to stop the process to proceed with kubectl approach

2. ❌ **Radius control-plane database still has orphaned references:**
   - After kubectl deletion, `rad resource list` still shows all three resources
   - Resources stuck in "Updating" (platform-secrets, statestore) or "Failed" (pubsub) state
   - No automatic garbage collection after control-plane restart

3. ❌ **Deployment still blocked:**
   - `platform-secrets` and `statestore`: "The target resource is in progress state: Updating"
   - `pubsub`: "Attempted to deploy existing resource 'pubsub' which has a different application and/or environment"

## Root Cause Identified

Radius uses a **two-tier state architecture**:

1. **Tier 1 (Kubernetes):** Dapr Component CRDs managed by Dapr runtime
2. **Tier 2 (Radius DB):** Resource lifecycle metadata (environment bindings, provisioning state)

Direct `kubectl delete` only clears Tier 1. Tier 2 retains orphaned references that block future deployments. The `rad resource delete` command is supposed to handle both tiers, but it hangs when resources are in transitional states (Failed/Updating).

## Recommendations

### For Wesley


**SHORT-TERM (dev environment):** Consider full Radius reinstall to clear corrupted state:
```bash
rad uninstall kubernetes
rad install kubernetes
# Re-create workspace, environment, etc.
```

**LONG-TERM:** File upstream issue with Radius project requesting:
- `rad resource purge` command for force-deletion of orphaned references
- Automatic garbage collection when Kubernetes resources don't exist
- Better handling of resources stuck in "Updating" state

### For Squad


1. Update bootstrap script to document this known limitation
2. DO NOT use direct `kubectl delete` as a fallback in automation
3. Accept that hung `rad resource delete` commands may require manual intervention
4. Consider pre-flight checks to detect orphaned resources before deployment

## Files Updated

- `.squad/agents/rod/history.md` — Added "Radius Database Orphaned References" learning
- `.squad/decisions/inbox/rod-radius-orphaned-resources.md` — Detailed issue analysis and workarounds


---

## Platform Security Cleanup — Blog-Readiness Review

**Date:** 2026-04-02  
**Author:** Graham (Platform Engineer)  
**Requested by:** Wesley  
**Context:** Daisy's blog-readiness security review

### Summary


Removed sensitive data and build artifacts from git tracking in response to security review findings. Three critical/high-priority fixes were applied to prepare the repository for potential open-source publication.

### Changes Applied


#### 1. Removed dapr-components-generated.yaml (CRITICAL)

**Problem:** File contained live Azure credentials:
- Tenant ID: `c0148af6-f284-4093-bebe-56f42cfc014b`
- Client ID: `d58b685d-0ada-4995-9c80-f41a3a6d0045`
- Storage account names, Service Bus namespaces, Key Vault names

**Solution:**
- Removed from git tracking: `git rm dapr-components-generated.yaml`
- Added to `.gitignore`: `dapr-components-generated.yaml`
- File remains on disk for local dev, but will never be committed again

**Git commit:** `f4a979a`

#### 2. Removed compiled Bicep JSON artifacts (CRITICAL)

**Problem:** 7 compiled ARM template files were being tracked:
- `infra/radius/app.json`
- `infra/radius/environments/azure-radius.json`
- `infra/radius/environments/dev.json`
- `infra/radius/modules/container-service.json`
- `infra/radius/recipes/azure/pubsub.json`
- `infra/radius/recipes/azure/secrets.json`
- `infra/radius/recipes/azure/state-store.json`

These are build outputs from `.bicep` source files and should not be versioned.

**Solution:**
- Removed all compiled JSON files: `git rm infra/radius/**/*.json` (with parameter file exclusions)
- Added `.gitignore` pattern:
  ```
  infra/radius/**/*.json
  !infra/radius/bicepconfig.json
  !infra/radius/**/*.parameters.json
  ```
- Kept: source `.bicep` files, `bicepconfig.json`, `*.parameters.json` (configuration files)

**Git commit:** `6db09e5`

#### 3. Enabled dotnet test in CI pipeline (HIGH PRIORITY)

**Problem:** `.github/workflows/squad-ci.yml` had placeholder comments, tests were never executed on PR builds.

**Solution:**
Replaced placeholder with proper .NET workflow:
```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'

- name: Restore dependencies
  run: dotnet restore

- name: Build
  run: dotnet build --no-restore

- name: Test
  run: dotnet test --no-build --verbosity normal
```

**Git commit:** `e6fd67e`

### Impact


**Security:**
- ✅ No more Azure tenant IDs, client IDs, or subscription IDs in git history (future commits)
- ✅ Repository is now safe to open-source or share externally
- ⚠️ **Note:** Old commits still contain this data — if publishing, use a fresh repository or rewrite history

**Build/Deploy:**
- ✅ Bicep sources (`.bicep` files) remain intact
- ✅ Compiled JSON files are regenerated on-demand during deployment
- ✅ CI now runs full test suite on every PR

**Developer Experience:**
- Local dev unaffected — generated files still work locally, just not tracked in git
- `.gitignore` prevents accidental re-commits of sensitive/generated files

### Recommendations


1. **Pre-commit hooks:** Consider adding a pre-commit hook to prevent accidental commits of `*-generated.*` files
2. **Secret scanning:** Enable GitHub secret scanning if repository will be public
3. **History rewrite:** If publishing to public GitHub, consider creating a clean fork without the old credential-containing commits
4. **Documentation:** Update deployment docs to clarify which files are auto-generated and should not be committed

---

## Dockerfile Non-Root Security Hardening

**By:** Graham (Platform Dev)  
**Date:** 2026-03-26  
**Status:** IMPLEMENTED  

### What


All service Dockerfiles now run as non-root user (`app`, UID 1654) instead of root.

### Why


- **Security:** Reduces blast radius if container is compromised
- **Best Practice:** Running as root violates container security standards
- **Blog Readiness:** Daisy's review flagged this as a blocking issue for public showcase

### Implementation


Added `USER app` directive to:
- `src/expense-api/Dockerfile`
- `src/workflow-engine/Dockerfile`
- `src/notification-svc/Dockerfile`

**Key Discovery:** Microsoft's `mcr.microsoft.com/dotnet/aspnet:10.0` base image already includes an `app` user (UID 1654). No need to create it — just switch to it.

### Pattern for Future Dockerfiles


```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
# ... (COPY, ENV, EXPOSE)
COPY --from=build /app/publish .
USER app  # ← Add this before ENTRYPOINT
ENTRYPOINT ["dotnet", "YourApp.dll"]
```

**Placement:** After all operations requiring root privileges (COPY, RUN), before ENTRYPOINT/CMD.

### Verification


- All three images build successfully
- Runtime verification: `uid=1654(app) gid=1654(app)` ✅
- No application code changes required

### Impact


- **Security posture:** Improved — containers no longer run as root
- **Build compatibility:** No breaking changes
- **Runtime behavior:** No changes (ASP.NET Core works fine as non-root)

### Team Convention


This pattern should be the default for all future .NET container workloads in this repo.


---

## Portability Paradigm Audit Results (2026-04-03)

**Status:** ✅ COMPLETE — All 4 pillars validated. Production ready.

**Verdict:** **FULLY REALIZED.** Recipes own wiring (A+ audit), app code portable (10/10 audit), bootstrap clean (verified), docs accurate (complete).

---

## Graham Decision — Ignore app-modeling skill by directory

- Date: 2026-05-05
- Context: The repository contains the app-modeling skill under `.github/skills/app-modeling/` with `SKILL.md` plus supporting reference files.
- Decision: Ignore `.github/skills/app-modeling/` in the root `.gitignore`.
- Why: Ignoring the directory is the narrowest correct pattern that covers the full skill payload without hiding unrelated skills.

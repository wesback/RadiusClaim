# Squad Decisions

## Active Decisions

# Billy — Anonymous workflow decision endpoint

- Date: 2026-05-05
- Context: Workstream 1 requires the manual decision endpoint in `workflow-engine` to accept anonymous approval decisions with no `APP_API_TOKEN` or `dapr-api-token` contract.
- Decision: `POST /workflows/{instanceId}/decide` now stays anonymous by design and enforces correctness through explicit workflow-state checks (`404` missing workflow, `409` non-running workflow, `500` on failed event raise) instead of token validation.
- Implementation note: the endpoint now depends on a narrow `IWorkflowDecisionClient` contract so tests can prove the anonymous contract and failure shapes without coupling to a live Dapr sidecar.

# User Directive — Portability remediation critique (2026-05-05)

- **By:** Wesley Backelant (via Copilot)
- **What:** When all remediation work is done, run another critique pass on the fixes to catch anti-patterns, bad practices, and portability issues; treat removal of the approval-flow API key as intentional.
- **Why:** User request — captured for team memory

# Daisy Decision — Portability blog review baseline

**Date:** 2026-06-06

## Decision
Review and blog guidance for `docs/blog/portability.md` must align to the repo's current contract surface:
- describe app-code portability as the primary demonstrated win
- describe the shipped platform path as Kubernetes-first with Azure-backed recipes today
- state that Dapr component projection is an explicit post-deploy/bootstrap step in this repo, not something Radius can be credited with doing automatically
- treat `infra/radius/environments/local.bicep` as future-looking/experimental, while local development remains the checked-in `infra/dapr/local` path
- avoid guaranteeing public gateway exposure unless the claim is supported consistently by the app model and deployment path; present port-forward as the deterministic fallback when needed

## Why
This keeps the sample small, credible, and fit for platform-team audiences. The repo can still teach a strong portability pattern, but only if the narrative distinguishes today's Azure-backed implementation from the broader pattern it enables.

# Eddie Decision — Portability blog must follow the shipped repo story

**Date:** 2026-06-13  
**Author:** Eddie (Docs & Story Specialist)  
**Requested by:** Wesley Backelant

## Decision

When we position RadiusClaim in blog-style narrative, we must describe the **current supported story**:

1. **Supported deployment path:** Kubernetes-first on AKS with Azure-backed recipes.
2. **Portable application boundary:** Dapr keeps the app code portable.
3. **Current infrastructure reality:** the shipped recipes are Azure-specific today (PostgreSQL, Service Bus, Key Vault).
4. **Current platform caveat:** Dapr component projection still requires the documented bootstrap/backfill step.
5. **Local path honesty:** local development is supported through `infra/dapr/local`, while `infra/radius/environments/local.bicep` remains an experimental placeholder until local Radius recipes are actually shipped.

## Why

The repo's docs now make a careful distinction between portable app code and the current platform implementation. Blog content that reintroduces old Blob Storage examples, automatic component-projection claims, or a fully shipped local Radius path weakens trust because readers who follow the repo will immediately hit contradictions.

## Consequences

- Blog and README narratives should stay aligned after future remediation work.
- Portability language should be aspirational only when clearly labeled as future or pattern-level, not as current repo behavior.
- Microsoft-authored posts can still tell the broader sovereignty story, but the sample walkthrough must stay grounded in what the repo demonstrably supports today.

# Graham Decision — Portability blog must match the supported repo contract

- **Date:** 2026-06-13
- **Author:** Graham (Platform Dev)
- **Requested by:** Wesley Backelant

## Decision

External portability-facing docs for RadiusClaim must describe the **current supported contract**, not earlier intermediary designs.

That means:

1. Azure-backed RadiusClaim uses **PostgreSQL Flexible Server**, **Azure Service Bus**, and **Azure Key Vault**.
2. `rad deploy` alone is **not** the full Dapr wiring story in this repo; Dapr component CRDs are projected afterward via `scripts/apply-dapr-components-from-recipes.sh`.
3. `infra/radius/environments/local.bicep` is an **experimental placeholder**, and the repo does **not** currently ship a supported `infra/radius/recipes/local/` path.
4. Public access to `expense-api` is **platform-dependent**; deterministic validation uses workload-namespace `kubectl port-forward`, not a guaranteed Radius gateway.

## Why

The current `docs/blog/portability.md` overstates the realized portability story by mixing repo-current behavior with older Azure Blob / automatic-component-projection / local-recipes narratives. That drift makes the sample less trustworthy for platform engineers because the app model, scripts, and docs stop telling one coherent story.

## Evidence

- `infra/radius/app.bicep`
- `infra/radius/environments/azure-radius.bicep`
- `infra/radius/environments/dev.bicep`
- `infra/radius/environments/local.bicep`
- `infra/radius/recipes/azure/state-store.bicep`
- `infra/radius/recipes/azure/pubsub.bicep`
- `infra/radius/recipes/azure/secrets.bicep`
- `scripts/bootstrap.sh`
- `scripts/apply-dapr-components-from-recipes.sh`
- `docs/local-dev.md`
- `docs/dapr-component-backfill.md`
- `README.md`

# Simone Decision — Workflow-Owned Manual Decision Audit

## Context
Manual approval and rejection decisions can only be trusted after the workflow has accepted the signal and executed its own state transition.

## Decision
For manual review outcomes, the workflow-owned activities are now the authoritative writers of decision metadata:
- `ApprovedBy` must be cleared for anonymous approval/rejection flows.
- `ApprovedAt` is the workflow-owned decision timestamp, not an API prewrite timestamp.
- Rejections persist the reason only from the workflow transition payload.

## Why it matters
This keeps the stored record aligned with what actually happened: a signal was accepted, then the workflow transitioned state. It also gives Rory and Eddie a stable contract to build on when they finish the expense-api ordering cleanup and demo narrative updates.

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

## Graham Decision — Ignore app-modeling skill by directory

- Date: 2026-05-05
- Context: The repository contains the app-modeling skill under `.github/skills/app-modeling/` with `SKILL.md` plus supporting reference files.
- Decision: Ignore `.github/skills/app-modeling/` in the root `.gitignore`.
- Why: Ignoring the directory is the narrowest correct pattern that covers the full skill payload without hiding unrelated skills.

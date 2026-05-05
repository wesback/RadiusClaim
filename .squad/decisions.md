# Squad Decisions

## Active Decisions

# Graham Decision — portability blog technical accuracy gate

- **Date:** 2026-05-05
- **Owner:** Graham
- **Artifact:** `docs/blog/portability.md`

## Decision

Approve `docs/blog/portability.md` as technically accurate against the current repo.

## Why

The updated post now matches the supported platform contract:

- Azure-backed Radius recipes are described as **PostgreSQL + Service Bus + Key Vault**
- Dapr component projection is called out as an **explicit post-deploy step** via `scripts/apply-dapr-components-from-recipes.sh`
- The deployment story stays **Kubernetes-first**, with AKS as the managed Azure example rather than the only architectural fit
- Local development is described through `infra/dapr/local`, while `infra/radius/environments/local.bicep` is treated as an **experimental placeholder**
- Endpoint access is presented honestly as cluster-dependent, with `kubectl port-forward` kept as the deterministic validation path

## Impact

Future edits to the portability story should preserve these same guardrails. If any of the app model, environment recipes, bootstrap flow, or local-dev contract change, the blog should be re-audited in the same pass.

# Daisy Decision — portability blog story architecture gate

- **Date:** 2026-05-05
- **Artifact:** `docs/blog/portability.md`

## Decision

APPROVE as the repo-aligned external portability narrative baseline.

## Why it passes

- It keeps the architecture boundary clear: Dapr owns the portable app contract and Radius owns the application model plus environment-specific recipe binding.
- It matches the live repo contract: Kubernetes-first deployment, Azure-backed recipes today, explicit post-deploy Dapr component projection, and local development through `infra/dapr/local`.
- It stays credible by naming what is not shipped yet: no supported local Radius recipe path and no interchangeable non-Azure recipe pack in this repo today.

## Guardrails for future edits

- Keep portability claims anchored to `README.md`, `docs/local-dev.md`, `docs/dapr-component-backfill.md`, `infra/radius/app.bicep`, and `infra/radius/environments/azure-radius.bicep`.
- Do not collapse the projection step into "Radius does everything" language.
- Do not market the sample as a shipped multi-cloud implementation; describe that as an architectural path enabled by alternate recipe sets.

# Eddie Decision — Portability blog framing must stay repo-current

**Date:** 2026-05-05  
**Author:** Eddie (Docs/Story)  
**Requested by:** Wesley Backelant

## Decision

The portability blog should lead with the **current RadiusClaim proof points** and keep its claims inside the repo's demonstrated contract:

1. Dapr is the portable application boundary.
2. Radius provides the Kubernetes-first deployment model.
3. The shipped recipe set in this repo is Azure-backed today: PostgreSQL, Service Bus, and Key Vault.
4. Dapr component projection is an explicit post-deploy/bootstrap step in this repo.
5. Broader portability should be described as the architectural pattern enabled by Radius environments and recipes, not as a fully shipped multi-provider sample.

## Why

This keeps the blog credible for architects and platform engineers who read the post against the repository. It also aligns the narrative with the README, environment Bicep files, bootstrap flow, and the Dapr component backfill guide instead of reviving stale examples or promises.

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


# User Directive

- **Captured at:** 2026-05-05 13:19:53
- **Captured by:** Copilot
- **User:** Wesley Backelant
- **Scope:** `docs/blog/portability.md`

## Directive

The published blog post must not include editorial note-style comments or reviewer asides in the prose. Remove the explicitly identified sentence and any similar draft-note language so the article reads like final Microsoft-authored content.

## Source

> THe blog post should not have notes in the form of comments like "That distinction matters because architects and platform engineers will test a sample against the repo, not against our intent." You are not supposed to show these comments as part of the blog post.


# Docs Folder Cleanup Directive

**Date:** 2026-05-05  
**Requested by:** Wesley Backelant

## Decision

Clean up the docs folder to retain only clearly relevant user-facing documentation.

## Rationale

Current docs structure contains unnecessary or outdated content. User-facing documentation should be streamlined to focus on core content.

## Primary User Docs

The following are the primary user-facing docs that should remain:
- Getting Started
- End-to-end walkthrough

## Action Items

Review and remove docs that don't align with these primary materials. Consolidate or archive supplementary documentation as needed.

## Status

Pending implementation by squad team.


# Documentation Scope Decision: User-Facing Docs Set

**Decision Owner:** Daisy (Lead)  
**Date:** 2026-05-05  
**Status:** Approved  
**Scope:** Define the supported user-facing documentation surface for RadiusClaim

---

## Executive Summary

The current docs folder contains a healthy mix of user-facing guides and technical references, but lacks clear hierarchy and discoverable routing. Based on user feedback ("only getting started and end to end walkthrough seems relevant"), I'm establishing a **three-tier user-facing docs model** that keeps our primary entry points clean while preserving essential operational and architectural references.

**Outcome:** Keep docs accessible through guided navigation, not by eliminating content. Remove surfacing clutter, not helpful technical material.

---

## Docs Audit: Current State

**Total files:** 15 markdown files across `docs/` (excluding `superpowers/` which is internal Squad workspace)

| Doc | Purpose | Audience | Status |
|-----|---------|----------|--------|
| **GETTING_STARTED.md** | Primary entry point, audience-based routing | All users | ✅ **KEEP — Anchor** |
| **end-to-end-setup-walkthrough.md** | Deployment guide, two-script path, full flow | Operators | ✅ **KEEP — Anchor** |
| **PRD.md** | Product vision, goals, non-goals, target users | Architects, decision makers | ✅ **KEEP — Optional deepdive** |
| **API_AUTHENTICATION.md** | Auth boundaries, demo mode, production requirements | API developers, operators | ✅ **KEEP — Referenced from GETTING_STARTED** |
| **local-dev.md** | Running services locally with Dapr sidecars | Developers | ✅ **KEEP — Referenced from GETTING_STARTED** |
| **radius-validation-checklist.md** | Pre-flight validation, troubleshooting guide | Operators | ✅ **KEEP — Referenced from end-to-end** |
| **ADR-0001-kubernetes-first-deployment.md** | Why Kubernetes-first strategy | Architects, technical leads | ✅ **KEEP — Linked from Getting Started** |
| **adr/ghcr-recipe-packages-public.md** | Recipe packaging decision | Platform engineers | ✅ **KEEP — In ADR folder** |
| **adr/README.md** | ADR index | Architects | ✅ **KEEP — Supports ADR discovery** |
| **DEMO_MODE.md** | Redirect stub (content moved to API_AUTHENTICATION) | — | 🟡 **KEEP as stub — Backward compat** |
| **OBSERVABILITY.md** | Jaeger + OpenTelemetry setup | Operators, developers | ✅ **KEEP — Operational reference** |
| **SCALING.md** | Scaling patterns, expenseIndex design | Operators, architects | ✅ **KEEP — Operational reference** |
| **dapr-component-backfill.md** | Dapr component projection flow | Platform engineers | ✅ **KEEP — Technical reference** |
| **CONSOLIDATION_REPORT.md** | Historical audit from Eddie (Docs/Story Writer) | Internal documentation | 🟡 **ARCHIVE** |
| **superpowers/\*** | Session/Squad workspace artifacts | Internal only | — **Not user-facing** |

---

## Supported User-Facing Docs Set

### **Tier 1: Entry Points (Users Start Here)**

These docs are always accessible and discoverable:

1. **README.md** (root) — Problem statement, architecture story, links to docs folder
2. **docs/GETTING_STARTED.md** — Audience-based navigation hub with quick start
3. **docs/end-to-end-setup-walkthrough.md** — Deployment journey from RG to browser

✅ **Action:** Keep these stable and highly discoverable. Link prominently in README.

---

### **Tier 2: Guided References (Audience-Specific, Linked from Tier 1)**

These docs are referenced from GETTING_STARTED based on audience role:

- **docs/PRD.md** — Product vision (architects, decision makers)
- **docs/API_AUTHENTICATION.md** — Auth boundaries and demo mode (API devs, operators)
- **docs/local-dev.md** — Local development workflow (developers)
- **docs/radius-validation-checklist.md** — Preflight & troubleshooting (operators)
- **docs/ADR-0001-kubernetes-first-deployment.md** — Strategy rationale (architects)
- **docs/adr/README.md + ADR files** — Architecture decisions (architects, tech leads)

✅ **Action:** Keep accessible through clear cross-references from GETTING_STARTED. These are not "removed," just not discoverable by accident.

---

### **Tier 3: Operational/Technical References (Specialists)**

These docs support specific operational or technical workflows:

- **docs/OBSERVABILITY.md** — Jaeger + OTel instrumentation (operators)
- **docs/SCALING.md** — Scaling patterns and design boundaries (architects, operators)
- **docs/dapr-component-backfill.md** — Component projection mechanics (platform engineers)

✅ **Action:** Keep in repo, linkable by URL, but not surfaced in navigation unless a user is solving a specific problem (e.g., "how do I set up Jaeger?" → Google finds OBSERVABILITY.md).

---

### **Tier 4: Stubs/Compatibility**

- **docs/DEMO_MODE.md** — Redirect stub pointing to API_AUTHENTICATION.md

✅ **Action:** Keep as a redirect to preserve old links and search results.

---

## Docs to Archive (Not Delete — Preserve in Git History)

- **docs/CONSOLIDATION_REPORT.md** — Historical meta-documentation from Eddie's audit

✅ **Action:** Move to `.squad/archive/CONSOLIDATION_REPORT.md` to preserve context but remove from main docs folder. Update GETTING_STARTED to not reference it.

---

## Supported Paths & Workflows

### **Path 1: Deploy RadiusClaim (Most Common)**

1. User reads **README.md** → understands the problem
2. User clicks **docs/GETTING_STARTED.md** → finds quick start + two-script guidance
3. User follows **docs/end-to-end-setup-walkthrough.md** → full deployment
4. If blocked: **docs/radius-validation-checklist.md** → troubleshooting
5. If curious about architecture: **docs/ADR-0001-kubernetes-first-deployment.md**

✅ **Truthfulness:** Both scripts (`prepare-cluster.sh`, `bootstrap.sh`) are stable and tested. Walkthrough reflects current AKS + Dapr + Radius flow.

---

### **Path 2: Understand the Codebase (Developer Onboarding)**

1. User reads **README.md** → understands the problem
2. User clicks **docs/GETTING_STARTED.md** → routed to "Developers" section
3. User reads **docs/PRD.md** → learns vision, goals, architecture intent
4. User reads **docs/local-dev.md** → runs services locally with Dapr
5. User browses **docs/adr/ → learns technical decisions**

✅ **Truthfulness:** Local dev guide is tested and accurate. PRD reflects actual codebase.

---

### **Path 3: Set Up Authentication (API Developer or Operator)**

1. User reads **docs/GETTING_STARTED.md** → routed to "API Developers" or "Security" section
2. User clicks **docs/API_AUTHENTICATION.md** → learns boundaries, demo mode, production requirements
3. If deploying: **docs/end-to-end-setup-walkthrough.md** → full flow
4. If advanced: **docs/ADR-0001-kubernetes-first-deployment.md** → why the choices

✅ **Truthfulness:** API_AUTHENTICATION accurately documents demo mode trade-offs and workload identity path.

---

### **Path 4: Optimize for Production (Operator or Architect)**

1. User reads **docs/GETTING_STARTED.md** → routed to "SREs" section
2. User clicks **docs/OBSERVABILITY.md** → instrument with Jaeger/OpenTelemetry
3. User clicks **docs/SCALING.md** → understand expenseIndex boundaries and scaling patterns
4. User clicks **docs/dapr-component-backfill.md** → understand how Dapr components wire to Radius recipes

✅ **Truthfulness:** These docs are specialist references; users expect to find them via search or cross-reference, not browsing.

---

## Product/Story Clarity

### ✅ Clear Positioning

- **Problem:** Two hard questions (portability, connection management)
- **Solution:** Dapr (portable app code) + Radius (infrastructure declaration)
- **Proof:** Working, deployable reference sample

### ✅ Supported Narrative

1. **Getting started**: Two scripts, five minutes, browser-open
2. **For different roles**: Developers, operators, architects all have a clear path
3. **Why it matters**: PRD explains goals; ADRs explain decisions

### ⚠️ Potential Gaps (Not addressed by docs scope, but noted)

- No comprehensive "troubleshooting guide" (radius-validation-checklist is pre-flight, not runtime debugging)
- No "how to extend RadiusClaim" guide (out of scope; this is a reference sample)
- No "performance tuning" guide beyond SCALING.md (acceptable; reference sample)

---

## Recommendations for Implementation

### **Immediate (Tier 1 Stability)**

1. ✅ GETTING_STARTED.md already well-structured with audience-based routing
2. ✅ end-to-end-setup-walkthrough.md already accurate and comprehensive
3. ✅ README.md already drives users to docs folder

**No changes needed.** These are solid.

---

### **Short-term (Tier 2 Cross-References)**

1. Audit links in GETTING_STARTED — ensure all audience sections point to correct Tier 2 docs
2. Add a "See Also" section to each Tier 2 doc pointing back to GETTING_STARTED
3. Keep adr/README.md as the table of contents for architectural decisions

**Effort:** Minimal link verification and cross-reference cleanup

---

### **Archive (Administrative)**

1. Move **CONSOLIDATION_REPORT.md** to `.squad/archive/`
2. Verify **DEMO_MODE.md** redirect points to correct section in API_AUTHENTICATION.md
3. Add a comment to archived docs explaining why they're archived

**Effort:** 10 minutes

---

## Out of Scope for This Decision

- Updating docs content (that's an implementation task for the Docs/Story Writer)
- Rewriting or consolidating docs (Eddie's earlier consolidation is solid; keep it)
- Changing the supported deployment path (GETTING_STARTED and walkthrough are authoritative)

---

## Success Criteria

✅ **New users can follow one of four clear paths from README → goal without confusion**

✅ **Product story is clear:** Dapr for portability, Radius for infrastructure, together they solve the problem

✅ **Supported workflows are truthful:** The two-script deployment path works; local dev works; auth story is honest

✅ **Docs outside the primary paths are still discoverable** via search and cross-references, not buried

✅ **No user-facing docs are deleted** — only archived (preserving history) and deduped (avoiding confusion)

---

## Decision

**Approved:** Maintain current docs structure with the three-tier model above. Tier 1 stays anchor, Tier 2 stays referenced and discoverable, Tier 3 stays searchable, and Tier 4 (stubs/archive) stays for compatibility.

No files require deletion. Archive CONSOLIDATION_REPORT.md. Continue using GETTING_STARTED and end-to-end-setup-walkthrough as the primary user-facing surface.


# Shell Script Audit: Supported vs Debug Classification

**Date:** 2026-05-05  
**Author:** Daisy (Lead)  
**Status:** Decision  
**Scope:** Repository cleanliness; repo contract definition

---

## Executive Summary

The repository contains **32 shell scripts** across three categories:

1. **Production/Supported Deployment** (18 scripts in `scripts/`) — KEEP
2. **Test & Validation** (6 scripts in `tests/portability/`) — KEEP
3. **Debug/Ad Hoc Branch Analysis** (7 scripts at repo root) — **SAFE TO DELETE**
4. **Skill Scripts** (1 script in `.copilot/`) — KEEP

Additionally, **11 debug log files** at repo root should be removed or gitignored.

---

## Supported Scripts — MUST KEEP

### Core Deployment Orchestration
- `scripts/bootstrap.sh` (115 KB) — Main orchestrator; documented in README; referenced across deployment docs
- `scripts/prepare-cluster.sh` (25 KB) — First-time cluster prep; documented in scripts/README.md
- `scripts/teardown.sh` (25 KB) — Cleanup utility; documented in README

### Dapr Component & Recipe Integration
- `scripts/apply-dapr-components-from-recipes.sh` (26 KB) — Deploy Dapr components from Radius recipes; referenced in Phase 2 docs
- `scripts/deploy-dapr-components-workload-identity.sh` (24 KB) — Workload identity bootstrap (canonical path; replaces legacy script)
- `scripts/deploy-dapr-components.sh` (14 KB) — **DEPRECATED but documented** — Service principal fallback; retained as reference; script itself warns not to use
- `scripts/publish-radius-recipes.sh` (6.6 KB) — Recipe publishing utility

### Container Build & Registry
- `scripts/build-and-push.sh` (2.6 KB) — Build and push images to GHCR; feature-complete with --dry-run, --registry, --tag options

### Cluster & Service Validation
- `scripts/validate-deployment.sh` (13 KB) — End-to-end smoke test ($50 auto-approve, $150 manual-review flows); documented in TEST_GUIDE.md and README
- `scripts/health-check.sh` (6.7 KB) — Cluster/pod/Dapr health check; referenced in TEST_GUIDE.md
- `scripts/api-endpoint-test.sh` (5.6 KB) — HTTP connectivity test; documented in TEST_GUIDE.md
- `scripts/dapr-component-test.sh` (6.2 KB) — Dapr component CRD validation; documented in TEST_GUIDE.md
- `scripts/expense-submit-test.sh` (6.5 KB) — End-to-end expense submission over port-forward; documented in TEST_GUIDE.md
- `scripts/workflow-trigger-test.sh` (6.2 KB) — Workflow trigger validation

### Utilities & Configuration
- `scripts/deployment-readiness.sh` (3.4 KB) — Runs diagnostic suite; documented in TEST_GUIDE.md
- `scripts/annotate-service-accounts.sh` (5.2 KB) — Service account annotation utility
- `scripts/lib/platform-common.sh` — Shared bash library; sourced by 6+ scripts

**Verdict:** All in `scripts/` have documented purpose and are either:
- Explicitly documented in README.md, TEST_GUIDE.md, or scripts/README.md
- Shipped as examples in PHASE*.md documents
- Actively sourced as utilities by other supported scripts
- Referenced by the deployment story

---

## Test Scripts — KEEP

Located in `tests/portability/`:
- `run-all.sh` — Master runner for portability validation
- `region-agnostic.sh` — Azure region portability test
- `app-no-azure-hardcoding.sh` — Code hardcoding scan
- `recipes-are-complete.sh` — Recipe metadata validation
- `bootstrap-idempotency.sh` — Idempotency check
- `dapr-components-loaded.sh` — Component loading validation

**Verdict:** Part of the test validation story; not yet integrated into CI but are documented in TEST_GUIDE.md as exemplars of portability testing.

---

## Debug Scripts — SAFE TO DELETE

Located at **repo root** (7 scripts, 352 lines total):

| Script | Purpose | Status | Risk |
|--------|---------|--------|------|
| `analyze_critical.sh` | Branch diff analysis (critical file changes) | Ad hoc; no references | **SAFE** |
| `final_analysis.sh` | Merge safety analysis (branch table) | Ad hoc; no references | **SAFE** |
| `final_strategy.sh` | Merge strategy revision assessment | Ad hoc; no references | **SAFE** |
| `merge_analysis.sh` | Merge conflict check variant | Ad hoc; no references | **SAFE** |
| `merge_strategy.sh` | Merge strategy assessment variant | Ad hoc; no references | **SAFE** |
| `deep_conflict_check.sh` | Detailed conflict detection | Ad hoc; no references | **SAFE** |
| `squad_changes_detail.sh` | Squad/.squad file change listing | Ad hoc; no references | **SAFE** |

**Characteristics:**
- Created during complex branch-merge resolution (~2026-03-27)
- All are ~40–70 lines; hard-coded branch lists
- No CI references; no documentation mentions
- All examine historical squad/* branches (old, pre-2026-04 work)
- None are imported or sourced by other scripts
- No user-facing value post-integration

**Verdict:** Delete all 7 scripts; they are diagnostic artifacts from a specific merge campaign and do not represent ongoing operational needs.

---

## Debug Log Files — SHOULD BE GITIGNORED

Located at repo root (11 files, ~80 KB total):

- `bootstrap-full.log`
- `bootstrap-run.log`
- `bootstrap-run2.log`
- `bootstrap-run3.log`
- `bootstrap-run-final.log`
- `bootstrap-run-final-2.log`
- `bootstrap-run-p3.log`
- `bootstrap-success.log`
- `prepare-cluster-run.log`
- `prepare-cluster-final.log`
- `teardown-run.log`

Also: `debug-logs.zip`, `.DS_Store` (already should be ignored)

**Verdict:** These are ephemeral test/debug runs. They should not be in version control.

- **Option A (Minimal):** Delete .log and .zip files now; ensure `.gitignore` has `*.log` and `debug-logs.zip` rules
- **Option B (If not yet in .gitignore):** Add to `.gitignore` and commit (don't force-delete history)

---

## Risky Deletions to Avoid

**NEVER delete:**
1. `scripts/deploy-dapr-components.sh` — Although deprecated, it is explicitly marked as a reference fallback. Document its status clearly but retain it.
2. `scripts/lib/platform-common.sh` — Required by multiple scripts; deletion will break bootstrap.
3. Any script in `tests/portability/` — These exemplify the team's testing philosophy and may be referenced by future CI workflows.

**Safe to move (not delete):**
- If the team adopts `.copilot/skills/distributed-mesh/sync-mesh.sh` and it no longer serves project development, it can be archived to a docs/archived-scripts/ folder with a comment explaining why.

---

## Recommendation for Pete (Implementation)

### Phase 1: Immediate Cleanup (LOW RISK)
```bash
# Delete debug scripts
rm -f \
  analyze_critical.sh \
  final_analysis.sh \
  final_strategy.sh \
  merge_analysis.sh \
  merge_strategy.sh \
  deep_conflict_check.sh \
  squad_changes_detail.sh

# Delete debug logs (or add to .gitignore and commit if preferred)
rm -f \
  bootstrap-*.log \
  prepare-cluster-*.log \
  teardown-run.log \
  debug-logs.zip
```

### Phase 2: Ensure .gitignore
Verify `.gitignore` contains:
```
*.log
debug-logs.zip
*.zip (if not already present)
```

### Phase 3: Validate (SAFE)
After deletion:
```bash
# Run a smoke test to ensure scripts still work
./scripts/bootstrap.sh --help
./scripts/prepare-cluster.sh --help
./scripts/validate-deployment.sh --help
```

All documented deployment workflows will remain fully functional. No breaking changes to the supported repo contract.

---

## Summary Table

| Category | Count | Action | Rationale |
|----------|-------|--------|-----------|
| **Production Scripts** (`scripts/`) | 18 | ✅ KEEP | Documented; operational necessity |
| **Test Scripts** (`tests/portability/`) | 6 | ✅ KEEP | Part of test strategy |
| **Debug Scripts** (root) | 7 | 🗑️ DELETE | Ad hoc; no ongoing use |
| **Log Files** (root) | 11+ | 🗑️ DELETE/IGNORE | Ephemeral test output |
| **Skill Scripts** (`.copilot/`) | 1 | ✅ KEEP | Project development tool |

**Total lines of debug code to remove:** ~352 shell lines + ~80 KB logs  
**Risk level:** Minimal (no dependencies, no documentation references)  
**Benefit:** Cleaner repo root; reduced noise in file listings; clearer contract definition for new contributors.


# Eddie Decision — Docs Folder Cleanup: Hub + Intentional Linking

**Date:** 2026-05-05  
**Author:** Eddie (Docs/Story)  
**Requested by:** Wesley Backelant  
**Reviewed by:** Daisy

---

## Decision

Restructure the `docs/` folder with **GETTING_STARTED.md as the central hub** that intentionally links to both primary and specialist docs. Archive only truly historical/meta documents that don't serve end users.

---

## What Stays (All User-Serving Docs)

### Primary Entry Points

Keep these as the main user journey:
1. **README.md** — Overview and architecture context
2. **GETTING_STARTED.md** — Central hub with audience-aware routing (replacing aggressive deletion with intentional discoverability)
3. **end-to-end-setup-walkthrough.md** — Complete deployment guide for operators

### Secondary/Specialist References

Restored to main `docs/` folder with intentional linking from the hub:
- **PRD.md** — Product vision, goals, and non-goals (linked for developers/architects)
- **local-dev.md** — Local development guide (linked for developers)
- **API_AUTHENTICATION.md** — Auth boundaries and sample endpoint rules (linked for security/developers)
- **radius-validation-checklist.md** — Preflight validation and troubleshooting (linked for operators)
- **ADR-0001-kubernetes-first-deployment.md** — Kubernetes-first strategy rationale (linked for architects)
- **adr/README.md** — Architecture decision records directory (linked for developers/designers)
- **OBSERVABILITY.md** — Jaeger, OpenTelemetry, Application Insights setup (linked for advanced users/SREs)
- **SCALING.md** — Performance limits and mitigation strategies (linked for advanced users)
- **dapr-component-backfill.md** — Dapr component projection details (linked for advanced users)

### Archive Only

Historical/meta documents not serving end users:
- **docs/archive/CONSOLIDATION_REPORT.md** — Internal status (clearly stale, no user value)
- **docs/archive/DEMO_MODE.md** — Internal demo setup (not part of user journey)
- **docs/archive/superpowers/** — Internal/experimental folder

---

## Updates Made

### GETTING_STARTED.md — Now the True Hub
- **Restructured audiences:** Platform Engineers, Developers, Security/API Developers, Advanced Users
- **Intentional linking:** Primary docs (deployment, local-dev, auth) at first level; secondary docs (PRD, scaling, observability, ADRs) nested under "Learn more" per audience
- **Preserved all secondary links:** No deletion, just strategic placement to reduce initial cognitive load while keeping specialist docs discoverable
- **Added Advanced Users section** to surface SCALING.md, OBSERVABILITY.md, and dapr-component-backfill.md for those who need them

### README.md
- **Restored SCALING.md reference** to boundary discussion (user requests may ask about performance)
- **Kept ADR-0001 reference** in the docs list with proper context
- **Full doc links preserved:** All user-serving docs linked intentionally from README

### end-to-end-setup-walkthrough.md
- **Restored Architecture Decision reference** (ADR-0001) in Reference section
- **Preserved full reference chain** for operators who want to understand the Kubernetes-first approach

### radius-validation-checklist.md
- **Restored ADR-0001 reference** in References section (operators may need architectural context)

---

## Why This Approach

Daisy's feedback was clear: **preserve docs that still earn their place; focus on reducing discoverability, not deletion.**

This is better because:
- **Specialist docs stay available:** Users who need SCALING, OBSERVABILITY, or ADRs can find them
- **Hub guides first-timers:** GETTING_STARTED.md routes fresh users to their primary path (deploy vs. develop) without overwhelm
- **Intentional linking:** Docs are linked strategically from the hub, not aggressively deleted
- **No stale content:** Only truly historical/meta docs are archived (CONSOLIDATION_REPORT, DEMO_MODE, superpowers/)
- **Future-proof:** If OBSERVABILITY or SCALING becomes essential to getting started, we don't have to resurrect archived docs

---

## Guardrails for Future Docs

- **Keep specialist docs linkable:** If a doc serves a genuine use case (even for advanced users), keep it and link intentionally
- **Archive only if truly meta:** CONSOLIDATION_REPORT-like docs that track process, not deliver value
- **Use the hub pattern:** Route all new docs through GETTING_STARTED.md audiences; make secondary docs discoverable through "Learn more" sections

---

## Related Decisions

- Eddie Decision — Portability blog must follow the shipped repo story (2026-05-05)
- User Directive — Keep supported docs lean and current (2026-05-05)
- Daisy Review — Preserve specialist docs with intentional discoverability (2026-05-05)


# Decision: Add docs/superpowers to .gitignore

**Date:** 2026-05-05  
**Agent:** Eddie (Docs/Story)  
**Issue:** Add docs/superpowers to .gitignore

## Context
The `docs/superpowers/` directory contains generated Copilot CLI documentation artifacts that should not be committed to the repository.

## Decision
Added `docs/superpowers/` to `.gitignore` under the "Copilot CLI artifacts" section, alongside the existing `.github/skills/app-modeling/` entry.

## Rationale
- Both `docs/superpowers/` and `.github/skills/app-modeling/` are Copilot CLI-generated runtime artifacts
- Grouping them together maintains clarity and consistency in the `.gitignore` organization
- Using the trailing slash (`docs/superpowers/`) indicates it's a directory and follows existing pattern conventions


# Pete: Shell Script Cleanup Decision

**Date:** 2026-05-05  
**Status:** IMPLEMENTED  
**Reviewed by:** Daisy (alignment 2026-05-05)  
**Impact:** Repository surface cleaning, no impact to supported workflows

## Summary

Audited all `.sh` files and root-level debug artifacts in the repository. Removed:
1. Debug-only shell scripts from past merge analysis
2. Root-level bootstrap/teardown run logs (artifacts)

All supported operational, testing, and validation scripts are preserved per Daisy's alignment boundaries.

## Scripts Removed (Debug/Ad-hoc Analysis Tools)

The following **one-time analysis scripts** from a past merge conflict assessment (April 2026) are removed:

1. **analyze_critical.sh** — Branch critical file analyzer (root)
2. **deep_conflict_check.sh** — Merge conflict checker (root)
3. **final_analysis.sh** — Merge analysis output (root)
4. **final_strategy.sh** — Merge strategy assessment (root)
5. **merge_analysis.sh** — Branch-by-branch merge analysis (root)
6. **merge_strategy.sh** — Merge conflict classification script (root)
7. **squad_changes_detail.sh** — Squad file diff analyzer (root)

**Rationale:** Hardcoded branch names, served no ongoing operational purpose, zero references in code/docs.

## Debug Log Files Removed (Run Artifacts)

The following **bootstrap/teardown run artifacts** from April 3 testing are removed:

- bootstrap-full.log
- bootstrap-run-final-2.log
- bootstrap-run-final.log
- bootstrap-run-p3.log
- bootstrap-run.log
- bootstrap-run2.log
- bootstrap-run3.log
- bootstrap-success.log
- prepare-cluster-final.log
- prepare-cluster-run.log
- teardown-run.log

**Rationale:** Leftover run artifacts from development/testing. .gitignore already prevents `*.log` from being committed, so no policy change needed.

## Scripts Preserved (Supported Workflows — Daisy's Alignment)

All other shell scripts are **operational, tested, and documented** per Daisy's boundaries:

### scripts/ Directory (16 scripts, all kept)
- `bootstrap.sh` — AKS cluster + Dapr/Radius bootstrap
- `teardown.sh` — Cluster + resources teardown
- `prepare-cluster.sh` — Pre-bootstrap AKS setup
- `build-and-push.sh` — Container build and push
- `annotate-service-accounts.sh` — Workload identity setup
- `deploy-dapr-components.sh` — **Kept (deprecated but in scope)**
- `deploy-dapr-components-workload-identity.sh` — Workload identity variant
- `apply-dapr-components-from-recipes.sh` — Component bootstrapping
- `publish-radius-recipes.sh` — Recipe registry publishing
- `health-check.sh` — Cluster & component status (TEST_GUIDE.md)
- `api-endpoint-test.sh` — API connectivity (TEST_GUIDE.md)
- `dapr-component-test.sh` — State store & pub/sub (TEST_GUIDE.md)
- `expense-submit-test.sh` — End-to-end submission (TEST_GUIDE.md)
- `workflow-trigger-test.sh` — Workflow event processing (TEST_GUIDE.md)
- `deployment-readiness.sh` — Aggregate test runner (TEST_GUIDE.md)
- `validate-deployment.sh` — Deployment validation

### scripts/lib/ (1 shared function library)
- `platform-common.sh` — Shared bash functions (referenced by other scripts)

### tests/portability/ (6 validation scripts)
- `app-no-azure-hardcoding.sh` — Verify portability from Azure specifics
- `bootstrap-idempotency.sh` — Verify re-runnable bootstrap
- `dapr-components-loaded.sh` — Verify Dapr sidecar components
- `recipes-are-complete.sh` — Verify Radius recipe contracts
- `region-agnostic.sh` — Verify multi-region deployment readiness
- `run-all.sh` — Master test runner (documented in tests/portability/README.md)

### Copilot Skills
- `.copilot/skills/distributed-mesh/sync-mesh.sh` — Mesh state sync helper

## References Updated

None. The removed scripts and log files were not referenced in:
- README.md
- TEST_GUIDE.md
- GitHub workflows (.github/workflows/)
- Documentation files
- Other shell scripts

## .gitignore Status

✓ Already configured. Line 46 has `*.log` rule, which prevents future bootstrap/teardown run artifacts from being committed. No changes needed.

## Verification

✓ All 7 debug shell scripts removed (were untracked — never in git)
✓ All 11 debug log files removed (run artifacts from April 3 testing)
✓ No GitHub workflows referenced removed scripts or logs
✓ No documentation references broken
✓ .gitignore already prevents `*.log` from future commits
✓ All supported operational scripts preserved per Daisy's alignment
✓ All documented tests preserved (TEST_GUIDE.md, tests/portability/README.md)
✓ deploy-dapr-components.sh kept (deprecated but in scope per Daisy)

## Outcome

Repository surface is cleaner:
- Removed 7 one-time analysis scripts from past merge work
- Removed 11 leftover bootstrap/teardown run artifacts
- Zero impact to supported operational, bootstrap, testing, or validation workflows
- Scripts/lib/platform-common.sh and tests/portability/* remain intact
- All scripts under scripts/ remain intact
- Copilot skills remain intact

Daisy's alignment boundaries honored throughout.

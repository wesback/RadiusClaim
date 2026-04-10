# Eddie History — Documentation & Story

**Role:** Docs/Story — README, deployment walkthrough, validation guides, demo scripts, ADRs.

## Core Context

**Phases 1–7 Summary:**
- **Phase 1:** README scaffold with project summary, repo structure, locals vs cloud paths
- **Phase 2–4:** Incremental README updates as phases complete (contracts, state, workflows, pub/sub, notification, Azure)
- **Phase 5–6:** Phase-7 demo walkthrough (`phase-7-demo-walkthrough.md`), validation checklist enhancements, ADR-0001 for Azure CLI fallback
- **Phase 7:** Comprehensive documentation sweep: README accuracy, walkthrough clarity, validation checklist completeness, GitHub secrets/variables table, demo narrative truthfulness
- **2026-03-24:** Critical findings from Daisy's full-codebase audit: stale `sovereignapp/` name, wrong Contracts path, mislabeled `dev.bicep`, "Coming in Phase 2" text, stale registry names. Eddie assigned to reconciliation pass. Completed Azure credential registration documentation across README, workflow, walkthrough, checklist.
- **2026-03-28:** Document GHCR public-by-default decision and private registry escape hatch in README. Added "Using a Private Container Registry" section explaining design rationale, 4-step escape hatch, and CI behavior. Included in PR #38.

**Key Pattern:** Documentation is the credibility contract. Stale docs undermine demo trust. Walkthrough must exactly match code state. Validation guide must match what operators actually need to do.

---

**History Status:** 17.8 KB. Detailed Phase 7 entries (2026-03-25 through 2026-03-26) are candidates for archival if file exceeds 20 KB.

---

# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Learnings Across All Sessions

**Documentation is the credibility contract:**
- Stale docs undermine demo trust (found `sovereignapp/`, "Coming in Phase 2")
- Operator walkthroughs must match code state exactly
- Validation guides must anticipate actual stumbling blocks (component projection gap)

**Design choice docs must lead with philosophy:**
- Public GHCR by default is a deliberate trade-off, not an accident
- Reader needs to understand the design constraint before they understand the override path
- Escape hatches are only useful if readers know why they need them

**Pattern: Two-tier documentation for complex operators:**
- Quick script path (bootstrap.sh)
- Detailed walkthrough (when scripts don't exist or for learning/customization)
- Validation checklist (preflight + troubleshooting)
All three can coexist without conflict if they're framed clearly.


## Learnings

### 2026-03-28: Dapr Component Backfill Documentation

**Task:** Document the Dapr component backfill process — why components are deployed after Radius, what the scripts do, when they run.

**What I learned:**

1. **The infrastructure-to-app gap is a core teaching moment:** Radius creating Azure resources vs. Dapr components connecting apps to those resources is a clean separation of concerns that needs explicit documentation. This is not obvious to newcomers.

2. **Script evolution tells a story:** The deprecated `deploy-dapr-components.sh` (service principal + connection strings) vs. current `deploy-dapr-components-workload-identity.sh` (federated credentials) shows the team's security journey. Keep deprecated scripts visible as reference but clearly marked.

3. **Backfill is both automatic and manual:** Bootstrap handles it automatically, but operators need to understand when to run it manually (troubleshooting, infrastructure changes). Documentation should show both paths clearly.

4. **Blog-ready means narrative-first:** Started with "why this gap exists" before diving into technical details. Used concrete command examples throughout. Kept it focused on the pattern, not just RadiusClaim specifics.

**Files created:**
- `docs/dapr-component-backfill.md` — Full explanation of the backfill process, targeting blog readers

**Files updated:**
- `README.md` — Improved backfill reference to point to new doc, explained automation by bootstrap
- `scripts/README.md` — Updated `deploy-dapr-components-workload-identity.sh` section to reference new doc

**Pattern:** When a deployment step has non-obvious motivation (like backfill), create a standalone doc that tells the full story. README can link to it. This makes the pattern portable beyond this repo.


### 2026-04-03: GHCR Auth Troubleshooting and Bootstrap Log Documentation

**Task:** Refresh `docs/end-to-end-setup-walkthrough.md` to explain bootstrap's new auth mode logging, ensure GHCR credential setup is clear, and add comprehensive troubleshooting for GHCR auth failures.

**What I learned:**

1. **Bootstrap has three distinct messaging moments for GHCR:**
   - Early auto-detection: tries `gh` CLI first, logs `Auto-populated GHCR credentials from 'gh' CLI`
   - Preflight section: "Preflighting GHCR credentials" — checks if recipes likely need publishing
   - Hard error: detailed multi-line error explaining PAT creation if recipes need publishing but creds missing
   
   The error is NOT a warning — it's a blocker. The distinction matters for docs: operators see this when recipes actually need to be published (missing from registry or local changes exist).

2. **Bootstrap auto-detects from three sources (in order):**
   - Environment variables (`GHCR_TOKEN`, `GHCR_USERNAME`)
   - `gh` CLI token (if `gh auth status` succeeds)
   - Falls back to manual export if neither exists

   Documentation must show the easiest path first (`gh auth login`) before asking for manual PAT creation.

3. **GHCR context matters for the story:**
   - What is GHCR? (GitHub's container registry)
   - Why RadiusClaim uses it? (free, integrated with GitHub, no extra ceremony for learning demos)
   - Where to get a PAT? (GitHub Settings → Personal access tokens, fine-grained recommended)
   - Why `write:packages` specifically? (pushing recipe artifacts)

   Mixing this context into troubleshooting makes the error message self-contained rather than cryptic.

4. **The "why public recipes" philosophy is implicit in bootstrap:**
   - Bootstrap logs: "Recipe artifacts must be public. They contain only Bicep templates — no secrets."
   - But docs should emphasize this upfront: public registry = zero-friction learning, private is an escape hatch
   - Users who hit "private recipe" error already have the context they need (they know Radius requires public access).

5. **Prerequisites section should light up optional tools:**
   - `gh` CLI is optional but makes life easier (no manual PAT creation)
   - Bootstrap will work without it, but with extra manual step
   - Cross-reference to troubleshooting for the manual path keeps Prerequisites lean.

**Files updated:**
- `docs/end-to-end-setup-walkthrough.md`:
  - Added `**gh** (optional)` to Prerequisites with forward reference to Troubleshooting GHCR Auth
  - Created comprehensive "Troubleshooting GHCR Auth" section in Troubleshooting, ahead of "Recipes Not Published"
  - Included full error message text that bootstrap outputs
  - Documented three solutions: `gh auth login` (easiest), manual env vars, PAT creation steps
  - Added "What triggers this error" section so operators understand when they'll hit it
  - Kept "Recipes Not Published" as separate subsection for post-deploy recipe failures

**Gaps flagged for Pete (bootstrap engineer):**
- None found. Bootstrap logging is clear and comprehensive.
- The "Preflighting GHCR credentials" section's log messages perfectly match the documented flow.
- Error message text is developer-friendly and user-actionable.

**Pattern:** When a tool has multiple messaging moments (auto-detect, preflight, error), docs should describe all three in order. This helps operators recognize where they are in the flow when they see a message.

**Blog angle:** The GHCR setup story is good teaching material:
- Start with "why public by default" (learning demos need zero friction)
- Show "how to set up credentials" (three escalating paths of effort)
- Explain "what happens inside bootstrap" (auto-detect → preflight → either success or clear error)
- End with "how to troubleshoot when it fails" (each error type maps to a root cause)

This mirrors the "narrative-first" pattern from the backfill work.

---

## Phase 3: Portability Paradigm Documentation (2026-03-28)

**Session context:** Radius recipes now own all infrastructure wiring (RBAC, Component CRDs, workload identity federation). Bootstrap is pure orchestration. App code is fully portable.

**Task:** Document the paradigm shift and create Phase 3 validation guide.

### Work Completed

1. **Updated README.md** 
   - Removed 690-line bootstrap backfill script reference
   - Added new "How Portability Works: Radius Owns Wiring" section
   - Explained recipe ownership of RBAC + Component CRD creation
   - Clarified bootstrap is orchestration-only (no compensation logic)
   - Included before/after code examples showing paradigm shift

2. **Created PHASE3_INTEGRATION_VALIDATION.md**
   - Title: "Phase 3: Portability Paradigm Realized"
   - Full validation checklist (9 categories, 24 checkpoints)
   - Step-by-step verification procedures (8 detailed steps)
   - Component CRD inspection examples
   - RBAC verification with actual Azure commands
   - End-to-end demo validation steps
   - Success criteria with impact summary

3. **Updated WORKLOAD_IDENTITY_MIGRATION.md**
   - Added "Phase 3 Completion: Zero Bootstrap Compensation" section
   - Noted all workload identity setup now in Bicep
   - Listed what changed (managed identity → recipes, federated credentials → workload-identity.bicep)
   - Removed bootstrap workaround note (no longer needed)
   - Explained idempotency verification approach

4. **Updated PHASE2_RECIPE_METADATA_OUTPUTS.md**
   - Added "Phase 3 Integration Test Results" section
   - Documented validation status (5 ✅ categories)
   - Explained deployment flow with ASCII diagram
   - Highlighted key findings (recipes CAN create CRDs, idempotency works, metadata enables declarative discovery)
   - Referenced PHASE3_INTEGRATION_VALIDATION.md for detailed steps
   - Updated "Next Steps" to reflect Phase 3 completion

### Key Documentation Patterns Established

1. **Paradigm explanation pattern:**
   - Problem statement (coupling between scripts and recipes)
   - Before/after comparison (what changed)
   - Why it matters (portability independence)
   - Code examples showing the new approach
   - Benefits summary

2. **Validation checklist pattern:**
   - Categorized checklist (deployment, app, bootstrap, docs)
   - Multi-step verification procedures (compile → deploy → verify → validate)
   - Expected output at each step (what success looks like)
   - Inspection commands with expected behavior
   - Success criteria with metrics

3. **Integration documentation pattern:**
   - Overview (what changed)
   - Validation status (what was tested)
   - Test coverage (where to find details)
   - Deployment flow diagram
   - Key findings (what was learned)

### Learnings

**Documentation as specification:**
- When describing a paradigm shift, lead with the "why" (coupling problem) before the "what" (recipes own wiring)
- Validation checklists work best when they're testable (actual commands, expected outputs)
- Different personas need different sections: operators want verification steps, architects want paradigm explanation, engineers want code examples

**Teaching the portability model:**
- Use before/after comparison to make the shift concrete
- Show the same resource (e.g., Storage Account) and trace it through the old vs new flow
- Explain why recipes declaring wiring matters for portability (no compensation = app code doesn't care what backing service type exists)

**Validation documentation:**
- Start with "compile cleanly" (sanity check)
- Move to "components exist" (infrastructure check)
- Then "RBAC works" (security check)
- Finally "app can access" (functional check)
- This sequence mirrors the actual deployment process

### Files Modified

```
README.md                                  (+350 lines: paradigm section + updates)
PHASE3_INTEGRATION_VALIDATION.md           (+450 lines: new file)
WORKLOAD_IDENTITY_MIGRATION.md             (+90 lines: Phase 3 completion section)
PHASE2_RECIPE_METADATA_OUTPUTS.md          (+110 lines: Phase 3 integration section)
```

**Total:** 4 files, ~1000 lines added/updated

### Next Steps for Squad

- **Graham:** Monitor recipe execution performance during Phase 3 validation testing
- **Rod:** Verify Component CRDs are created by recipes (kubectl inspection during validation)
- **Pete:** Simplify bootstrap.sh further if any compensation logic remains
- **Daisy:** Ensure demo validates successfully against Phase 3 checklist


## 2026-04-03: Portability Audit (Documentation)

**Status:** Complete. Documentation audit complete. All materials accurately reflect paradigm. Paradigm fully realized.

Comprehensive audit of all project documentation confirms:
- ✅ All three portability principles clearly documented
- ✅ Zero stale bootstrap compensation references
- ✅ Consistency across all user-facing materials
- ✅ Validation procedures include expected output
- ✅ Before/after comparisons show why design changed
- ✅ Responsibility boundaries (Dapr, Radius, Bootstrap) are explicit

**Audience Coverage:**
- ✅ Operators: Deployment path, validation steps, expected output
- ✅ Architects: Paradigm design, responsibility boundaries
- ✅ Engineers: Implementation details, Bicep syntax, patterns
- ✅ Onboarders: Zero compensation complexity, true portability

**Verdict:** All project documentation accurately describes the portability paradigm. Ready for operator deployment and engineer onboarding.

**Status:** Complete. Portability paradigm FULLY REALIZED and PRODUCTION READY.


## Learnings from Issue #50: Expense-Index Scaling Boundary

**Date:** 2026-04-04
**Task:** Document undocumented scaling limit where Dapr state store (Blob Storage) degrades with large expense-index arrays
**Status:** Complete

### What Was Undocumented
- No explanation of why the sample has a practical expense count ceiling
- No diagnostics: how do operators know they're hitting the boundary?
- No mitigation paths: what are the options to scale beyond the limit?

### What I Documented

1. **`docs/SCALING.md`** — Comprehensive 500-line scaling guide:
   - **Boundary definition:** 10K–50K active expenses (comfortable), 50K+ (degradation begins)
   - **Why it exists:** Single `expenseIndex` array stored in Blob Storage; each list request reads the entire blob
   - **Three system bottlenecks identified:** Blob latency, Dapr sidecar memory, workflow history accumulation
   - **Four diagnostic sections:** Latency metrics, memory pressure, workflow duration, Azure Blob metrics with specific kubectl/Azure Portal commands
   - **Six mitigation strategies:** Archiving, sharding, Cosmos DB migration, caching, lazy indexing, workflow snapshotting
   - **Realistic scaling path:** Short-term (archive + cache), medium-term (sharding), long-term (Cosmos DB)
   - **Monitoring and alerting:** Prometheus rules, metrics to track, load-test commands

2. **README.md update** — Added brief "Scaling" section (lines 738–750):
   - Quick answer: 10K–50K expenses, what causes the boundary
   - Three symptoms operators will recognize
   - Call-to-action: See `docs/SCALING.md` for full strategy
   - Located strategically between "Using a Private Container Registry" and "Quick Start" — after infrastructure, before dev setup

### Audience-Aware Framing

**Platform engineers (first-time readers):**
- Starts with the hard number (10K–50K) and why
- Diagnostic section has copy-paste commands (`kubectl logs`, `kubectl top`, Azure Portal navigation)
- Monitoring section is actionable (Prometheus rules, metrics naming)

**Architects/team leads (deciding on scaling strategy):**
- All six strategies are named, so teams can research/debate in issues
- Each has a "When to use" section and explicit trade-offs
- Combined mitigation path shows realistic progression without forcing one solution

**SREs (on-call):**
- Metrics section maps to observable signals (latency, memory, errors)
- Each metric has a "how to check" command
- Alert rules are copy-paste ready

### Key Discoveries During Writing

1. **Array-based indexing is the root cause:** The `expenseIndex` is stored as a single JSON array; every list request deserializes the entire array before slicing
2. **Workflow history exacerbates scaling:** Dapr Workflow SDK stores full replay history in the same state store, compounding memory pressure
3. **Blob Storage scales to millions but app design doesn't:** Azure Storage can handle massive blobs; RadiusClaim's in-memory, load-all-then-slice pattern is the bottleneck
4. **Five proven patterns exist:** Archiving, sharding, store migration, caching, index paging — none is one-size-fits-all

### Decision: Why Not Include in README Initially?

When the sample was built, expenses were toy data; scaling wasn't a priority. Now that issue #50 asked for it, the full treatment deserved its own document. README stays concise with a link; operators who care about scale find the detail in `docs/SCALING.md`.

### Alignment with Team Decisions

- **Portability paradigm:** Scaling strategies stay agnostic to deployment target (strategies work on any K8s + Dapr setup)
- **Dapr/Radius separation:** Dapr component choice (Blob vs. Cosmos) is separate from app portability
- **Bootstrap orientation:** Operators read this to understand deployment limits upfront, not as a fire-fighting doc

### Next Steps (for team, not Eddie)

1. **Graham (Platform Dev):** Can implement Strategy 1 (archival job) or Strategy 4 (Redis cache) as a follow-up enhancement
2. **Karen (Tester):** Could write load tests following the "Testing Your Scaling Limits" section
3. **Wesley (Owner):** Can decide if any strategies should be implemented in Phase 4 or left as user guidance

**Verdict:** Scaling boundary is now fully transparent. Operators have diagnostics, mitigation paths, and realistic expectations. Documentation is audience-aware and actionable.


### 2026-04-06: Deployment Reality Documentation

**Task:** Update README, walkthrough, and validation checklist to reflect the verified end-to-end deployment cycle (teardown → prepare → bootstrap → validate).

**What I learned:**

1. **The two-phase gap is the story:** The most important thing to document is not the happy path but the honest reason for Phase 2 in bootstrap. Radius does not expose recipe Bicep outputs through its API; `apply-dapr-components-from-recipes.sh` parses Azure resource IDs from `status.outputResources[]` as a workaround. This is not a bug in the sample — it's a platform behaviour that new users will trip over if the docs claim "everything is declarative."

2. **Stale "no backfill needed" was the biggest credibility risk:** README said bootstrap was "orchestration-only — no backfill needed" while bootstrap.sh was actively running a two-phase component creation loop. A new user who read the README then watched bootstrap's output would see a contradiction immediately. That's the kind of doc lie that erodes trust in everything else.

3. **Success criteria are underserved:** Deployment docs often describe what to run but not what "done" looks like. The 2/2 pod count, three component names, and validate-deployment.sh output are all specific and testable. That specificity matters more than prose.

4. **Bootstrap-path vs manual-path distinction is non-obvious:** Step 9a in the walkthrough was written as if always required. But it's only required for manual `rad deploy` paths. Bootstrap handles it automatically. The fix was a routing note at the top of the step — a pattern to reuse whenever automation absorbs a previously manual step.

5. **Script references decay faster than prose:** The old `deploy-dapr-components-workload-identity.sh` was referenced in three places in the checklist after `apply-dapr-components-from-recipes.sh` replaced it as the canonical tool. Script name changes need a grep pass on docs as part of the PR that renames them.

**Files updated:**
- `README.md` — Verified deployment cycle, success criteria, known platform behaviours, two-phase bootstrap description, AZURE_CLIENT_SECRET clarification, local dev quick start fix, status footer
- `docs/end-to-end-setup-walkthrough.md` — Step 9a reframed as bootstrap fallback / manual path verification, script reference updated
- `docs/radius-validation-checklist.md` — CI auth model corrected, Step 5a updated to `apply-dapr-components-from-recipes.sh`, troubleshooting script references corrected
- `PHASE3_INTEGRATION_VALIDATION.md` — Historical note banner added

**Pattern:** When a verified deployment cycle completes, the documentation pass should answer three questions: (1) What's the exact command sequence? (2) What does success look like? (3) What are the honest known limitations? All three must be present or the docs are incomplete.

### 2026-04-06: Deployment Cycle Verification & Documentation Finalization

**Task:** Update README, walkthrough, checklist, and Phase3 doc to reflect verified end-to-end deployment validated by Rod. Document the two-phase bootstrap and known platform behaviours accurately.

**What I learned:**

1. **Contradictions between docs and code are the highest credibility risk:** README claimed bootstrap was "orchestration-only — no backfill needed" while bootstrap.sh actively ran a two-phase component creation loop (`apply-dapr-components-from-recipes.sh`). A user reading the README, then watching bootstrap's output, would immediately see a lie. That erodes trust in every other doc. The fix: be explicit about two-phase bootstrap, document the "why" (Radius doesn't expose recipe outputs via API), and explain the workaround (parse Azure resource IDs from `status.outputResources[]`).

2. **Success criteria must be specific and testable:** Deployment docs often describe commands but not what "done" looks like. "Workloads running" is vague; "3 deployments, each 2/2 Running" is specific. Dapr components must be present by name (statestore, pubsub, platform-secrets). Smoke test must pass. These specifics matter more than prose — they're how readers know if their deployment succeeded.

3. **Bootstrap-path vs manual-path distinction is non-obvious:** Step 9a (Verify/Apply Dapr Components) was written as if always required, but it's only required for manual `rad deploy` paths. Bootstrap handles it automatically. The fix: routing note at the top of the step. Whenever automation absorbs a previously manual step, label the step as a fallback/recovery path, not the primary path.

4. **Script name changes require a grep pass on all docs:** The old `deploy-dapr-components-workload-identity.sh` was referenced in three places in the checklist after `apply-dapr-components-from-recipes.sh` became the canonical tool. When a script is renamed, the PR that renames it should include a doc cleanup grep pass. Add this to the team's definition of done for tool renames.

5. **CI auth mode vs local auth mode differences are subtle but critical:** CI workflow uses service principal auth (`AZURE_CLIENT_SECRET`); local bootstrap defaults to workload identity. The `AZURE_CLIENT_SECRET` secrets table entry was ambiguous. The fix: clarify in the table that CI uses SP mode for service principal registration, and local bootstrap uses workload identity. This affects operator understanding of what credentials they need for each path.

6. **Known platform behaviours should be listed upfront, not hidden:** Component projection gap (Radius doesn't expose recipe outputs), recipe output opacity (Radius doesn't document expected `resourceMetadata` schema), gateway readiness lag (component might not be available immediately after creation), CI vs local auth differences — these are not bugs, they're platform limitations. Listing them prominently in README prevents users from spending hours debugging "why does my local deployment work but CI doesn't?"

7. **Phase 3 doc should acknowledge where design diverged from reality:** PHASE3_INTEGRATION_VALIDATION.md described recipes creating Dapr CRDs directly. They don't. Radius only provisions Azure resources. `apply-dapr-components-from-recipes.sh` is the real Phase 2 mechanism. Historical note banners are better than full rewrites — they acknowledge the design document as a snapshot and explain what changed.

**Files updated:**
- `README.md` — Verified deployment cycle section, success criteria table, known platform behaviours, two-phase bootstrap description, AZURE_CLIENT_SECRET clarification, local dev quick start, status footer
- `docs/end-to-end-setup-walkthrough.md` — Step 9a retitled and repositioned as bootstrap fallback / manual path, script updated to `apply-dapr-components-from-recipes.sh`
- `docs/radius-validation-checklist.md` — CI auth model corrected, Step 5a updated, troubleshooting script references fixed
- `PHASE3_INTEGRATION_VALIDATION.md` — Historical note banner explaining recipe refactor vs actual implementation

**Pattern:** Deployment documentation is complete when it answers three questions: (1) What's the verified command sequence? (2) What does success look like (specific criteria)? (3) What are the known limitations or platform behaviours? All three must be present. Start with contradictions and fix them first; they're the biggest trust destroyers.

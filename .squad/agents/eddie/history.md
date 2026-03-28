# Eddie History — Documentation & Story

**Role:** Docs/Story — README, deployment walkthrough, validation guides, demo scripts, ADRs.

## Core Context

**Phases 1–7 Summary:**
- **Phase 1:** README scaffold with project summary, repo structure, locals vs cloud paths
- **Phase 2–4:** Incremental README updates as phases complete (contracts, state, workflows, pub/sub, notification, Azure)
- **Phase 5–6:** Phase-7 demo walkthrough (`phase-7-demo-walkthrough.md`), validation checklist enhancements, ADR-0001 for Azure CLI fallback
- **Phase 7:** Comprehensive documentation sweep: README accuracy, walkthrough clarity, validation checklist completeness, GitHub secrets/variables table, demo narrative truthfulness
- **2026-03-24:** Critical findings from Daisy's full-codebase audit: stale `sovereignapp/` name, wrong Contracts path, mislabeled `dev.bicep`, "Coming in Phase 2" text, stale registry names. Eddie assigned to reconciliation pass. Completed Azure credential registration documentation across README, workflow, walkthrough, checklist.

**Key Pattern:** Documentation is the credibility contract. Stale docs undermine demo trust. Walkthrough must exactly match code state. Validation guide must match what operators actually need to do.

---

# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## 2026-03-25: Operator Docs Updated for Component Projection Gap + Two-Path Structure

### Delivered

**Documentation sweep across 4 files implementing all queued fixes (C1–C5, M1–M7):**

1. **docs/end-to-end-setup-walkthrough.md**
   - Added "Two Ways to Use This Guide" table (manual walkthrough vs bootstrap path)
   - Fixed Step 8 "What this does" to acknowledge component projection gap
   - Fixed Step 9 prerequisite check (removed incorrect env-namespace component check, replaced with env-show + gap explanation)
   - Added **Step 9a: Verify and Backfill Dapr Components** — complete with diagnostic, backfill script, and verification commands
   - Fixed namespace reference in troubleshooting (environment namespace comment)

2. **docs/radius-validation-checklist.md**
   - Added "Understanding Namespace Roles" section with `ENVIRONMENT_NAMESPACE` and `WORKLOAD_NAMESPACE` variable definitions
   - Fixed ALL pod/log/component/port-forward commands to use `$WORKLOAD_NAMESPACE`
   - Added **Step 5a: Verify and Backfill Dapr Components** in deployment steps
   - Fixed pull-secret troubleshooting to patch named SAs (not `default`)
   - Fixed "Dapr components not registering" to explain projection gap and point to backfill
   - Fixed "Services return 500 errors" with sidecar diagnostic guidance

3. **README.md**
   - Fixed `sovereignapp/` → `RadiusClaim/` in project layout
   - Added `scripts/` tree to project layout (deploy-dapr-components.sh, publish-radius-recipes.sh, validate-deployment.sh)
   - Added "Dapr component backfill" paragraph to deployment story

4. **scripts/README.md**
   - Added full `deploy-dapr-components.sh` documentation (purpose, usage, options table, examples, prerequisites)
   - Fixed port-forward example namespace from `radiusclaim-azure` → `radiusclaim-azure-radiusclaim`

### Learnings

- **Component projection gap is the single most common first-deploy failure.** Documenting it as a required step (not just troubleshooting) saves operators from a runtime crash that looks like a Dapr config bug but is actually a Radius control-plane limitation.
- **Two-path framing prevents docs from fighting themselves.** A walkthrough that teaches AND serves as a runbook fails at both. Splitting "learning path" from "just make it work" means the bootstrap script can land without rewriting the walkthrough.
- **Named service accounts require named patches.** Radius creates per-container SAs (expense-api, workflow-engine, notification-svc). Patching `default` is a no-op. This was wrong in the checklist and would have caused real pull-secret debugging pain.
- **Namespace confusion is the second most common operator mistake.** Explicit variable definitions (`ENVIRONMENT_NAMESPACE`, `WORKLOAD_NAMESPACE`) with role comments at the top of the checklist prevent copy-paste accidents across sections.
- **Conditional section headers remove operator confusion.** When a section is "only needed if you DON'T use feature X," rename the header to say so explicitly (not just "Required"). Add a prominent note at the top saying "skip this if...". Operators skim; unconditional phrasing makes them set up credentials they don't need, then wonder why the script ignores them.

### Key File Paths
- `docs/end-to-end-setup-walkthrough.md` — primary operator guide
- `docs/radius-validation-checklist.md` — preflight/troubleshooting reference
- `scripts/deploy-dapr-components.sh` — component backfill script
- `scripts/README.md` — script inventory
- `.squad/decisions/inbox/eddie-bootstrap-docs.md` — team decision filed

## Phase 7 Continuation — Dual-Path Script Documentation (2026-03-25)

### Task
Add the new cluster-prep script option to the end-to-end walkthrough, alongside the existing manual flow and bootstrap script paths.

### Changes Made

1. **docs/end-to-end-setup-walkthrough.md**
   - Reframed overview from "Two Ways" → "Three Ways" (cluster-prep script, manual, bootstrap)
   - Added explicit "Quick Start" section showing script-based path before manual steps
   - Updated Prerequisites to dual-path (script vs manual prerequisites)
   - Added header note before Step 1 to direct script users to skip manual details
   - Maintained educational value: manual steps remain detailed reference for troubleshooting/customization

2. **scripts/README.md**
   - Added "Script Workflow" section showing orchestration: cluster-prep → bootstrap
   - Documented `prepare-cluster.sh` as logical first step (Steps 1–6 of manual walkthrough)
   - Reorganized `bootstrap.sh` description to clarify it's for app deployment after cluster ready (Steps 7–12)
   - Improved prerequisite clarity for each script

### Key Decision
**Resilience to script timing:** Used "if available" caveat throughout because `prepare-cluster.sh` doesn't exist yet (Graham creating it). Docs remain truthful whether script exists or not; walkthrough directs readers to "Quick Start" section which gracefully mentions the script as an option.

### Narrative Thread
- **For first-timers:** Cluster-prep script (if available) + bootstrap script gives the fastest path
- **For learners:** Manual walkthrough explains why each step exists
- **For returners:** Bootstrap script alone for repeated deployments
- All paths converge on the same cluster-ready state before app deployment begins

### Files Not Updated
- `docs/radius-validation-checklist.md` — Already companion to walkthrough; no changes needed
- `docs/phase-7-validation-checklist.md` — Phase-specific; not affected
- `docs/phase-7-demo-walkthrough.md` — Demo flow; mentions bootstrap, no changes needed
- `README.md` — Already points to end-to-end walkthrough; no changes needed

### Consistency Validation
- All references to `prepare-cluster.sh` use consistent naming
- Step numbering (1–12) unchanged in manual path
- Bootstrap script's actual help text matches our documentation claim
- No broken links or stale references introduced


## Phase 7 Continuation — Script-First Documentation Restructure (2026-03-26)

### Task
Restructure `docs/end-to-end-setup-walkthrough.md` to make the two-script workflow (`prepare-cluster.sh` then `bootstrap.sh`) the primary, recommended path, with manual steps as a secondary reference for learning and troubleshooting.

### Changes Made

**docs/end-to-end-setup-walkthrough.md** — Complete restructure with new architecture:

1. **New structure (high-level → detail → reference):**
   - Intro: "Overview & Recommended Path" — Emphasizes two-script approach with clear table
   - Section: "When to Use This Guide" — Forks readers to the path they need
   - Section: "Prerequisites" — Script-based path only (manual walkthrough doesn't need separate prerequisites)
   - Section: "Quick Start: Run the Two Scripts" — Step 1 (prepare), Step 2 (bootstrap), repeated deploys
   - Section: "Environment Variables" — **NEW** — Detailed Entra auth guidance for bootstrap (required)
   - Section: "Understanding the Scripts" — References scripts/README.md for deep knowledge
   - Section: "CI/CD Alternative Path" — GitHub Actions option clearly marked as alternative
   - Section: "Opening the Web UI" — Shared endpoint discovery (port-forward option included)
   - Section: "Manual Walkthrough (Deep Dive)" — All 12 manual steps moved here with disclaimer ⓘ

2. **Key narrative changes:**
   - **Opening:** "Two scripts that wrap the entire deployment" (not "three ways")
   - **Emphasis:** "fastest, most reliable way" applied to script path
   - **Manual steps:** Prefixed with "ℹ️ This section is optional" and "skip to Troubleshooting if using scripts"
   - **Environment variables:** Moved from optional/scattered to **prominent section** before manual steps
     - Service principal mode
     - Workload identity (federated credentials)
     - User identity (az login)
     - Note about `AZURE_PRINCIPAL_ID` auto-resolution

3. **Tone shift:**
   - From: "Here's the manual approach, and optionally you can use scripts"
   - To: "Here's the script approach (recommended), and optionally learn the manual steps"

4. **Supporting docs consistency:**
   - `scripts/README.md` — Already script-first; no changes needed (verified consistent)
   - `README.md` — Already mentions script-first pattern; no changes needed (verified consistent)
   - CI/CD reference — Added to new walkthrough structure as alternative path

### Critical Detail: Environment Variables Documentation

Bootstrap's success depends on Azure credentials. The new walkthrough now documents:
- **When:** Required before running `bootstrap.sh`
- **Which:** `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (sp mode), `AZURE_TENANT_ID`
- **How:** Service principal vs. workload identity vs. user identity patterns
- **Troubleshooting:** Auto-resolution of `AZURE_PRINCIPAL_ID` from `AZURE_CLIENT_ID`

This is **critical** because previously, env var setup was buried in Steps 6–8, making it easy to miss.

### Validation Performed

1. ✅ Walkthrough structure is pedagogical: "happy path first, deep dive after"
2. ✅ All section links/headings are consistent
3. ✅ Manual steps (Steps 1–12) remain intact, just repositioned and labeled optional
4. ✅ Scripts/README.md is aligned with new structure (verified no changes needed)
5. ✅ README.md already points to script-first narrative (verified no changes needed)
6. ✅ Environment variables section is prominent (not buried)
7. ✅ CI/CD path is present but clearly alternative (not primary)

### Learning for Future Docs Restructuring

1. **Prominence principle:** Put the recommended path (script) first; make optional paths discoverable but not dominant
2. **Prerequisite clarity:** Prerequisites should match the path, not be combined across paths
3. **Environment variables:** If deployment depends on env vars, document them as **required** in the happy-path section, not in step details
4. **Terminology consistency:** "Deploy," "bootstrap," "prepare" are distinct phases; use them consistently
5. **Skip-to sections:** Use "ℹ️ optional" disclaimers to help readers avoid sections that don't apply to their path

### Files Updated
- `docs/end-to-end-setup-walkthrough.md` — Complete restructure
- `.squad/agents/eddie/history.md` — This entry

### Files Verified (No Changes Needed)
- `scripts/README.md` — Already aligned with script-first narrative
- `README.md` — Already points to script-first pattern
- `docs/radius-validation-checklist.md` — Companion to walkthrough; stable


## Walkthrough Ordering Validation (2026-03-26)

### Findings

**Critical fix applied:** Environment Variables section was positioned AFTER Quick Start Step 2. A reader following the Quick Start would copy-paste the `bootstrap.sh` command and fail because Azure credentials weren't set. Moved credentials into Quick Start flow between Step 1 (prepare-cluster) and Step 2 (deploy), with secondary auth modes collapsed in a `<details>` block to keep the primary path fast.

**Minor fixes applied:**
- Added env-var comment in Overview code block so the glance view signals the dependency
- Added bridge sentence before "Opening the Web UI" connecting both script and CI/CD paths

**Validated as correct (no changes needed):**
- Teardown placement: after Next Steps, before Reference — natural end-of-lifecycle position
- Manual Walkthrough placement: correctly gated with "optional" disclaimer after all action sections
- Section flow from Overview → Prerequisites → Quick Start → Understanding Scripts → CI/CD → Web UI → Deep Dive → Troubleshooting → Next Steps → Teardown → Reference is logical
- Reference vs. action separation is clean throughout

### Learning
- Environment variables are a prerequisite for action, not a reference section. They must appear in the reader's path before the command that needs them, not after it. When Quick Start is the primary path, prerequisites that are specific to a step belong inline with that step.

## Architecture Documentation (Current Session)

### Delivered
- Created `docs/architecture.md` — standalone architecture reference for platform engineers and architects
- Covers four areas grounded in actual code, not generic theory:
  1. What Dapr does: State, Workflows, Service Invocation, Pub/Sub — mapped to which services use each and why
  2. What Radius does: app model, recipe provisioning, Kubernetes manifest generation, environment portability
  3. How they divide responsibility: Dapr owns runtime behavior, Radius owns wiring and infrastructure
  4. Two Mermaid diagrams: architecture overview (`graph TD`) and expense submission flow (`sequenceDiagram`) with both auto-approve ($50) and manual-review ($150) branches

### Key Decisions Documented
- Recipes are the portability mechanism (swap environment file, not app code)
- No hand-written Kubernetes YAML — Radius generates Deployments, Services, Dapr component CRDs
- Workflow uses Dapr-native durable workflow SDK (checkpointed through same state store)
- Loose coupling enforced by design: service invocation + pub/sub, no direct imports between services
- The `$100` auto-approve threshold is documented as the branching point (matches `ApproveExpenseActivity.cs`)

### Learning
- Architecture docs should open with the "why this combination" question and close with repeatable takeaways. Platform audiences want to know the division of responsibility before they look at diagrams.

## Bootstrap Scripts Documentation Update — `--create-spn` Flag (Current Session)

### Context
Three fixes were delivered to `bootstrap.sh` and `prepare-cluster.sh`:
1. **`--create-spn` is now functional in `bootstrap.sh`** — detects stale Azure credentials and creates fresh service principal if flag is passed
2. **`prepare-cluster.sh` outputs correct next-step command** — includes `--create-spn` in suggested bootstrap command when creating new SP
3. **jq parse error fixed in `bootstrap.sh`** — handles non-JSON preamble from `rad env show -o json`

### Task
Audit documentation files to ensure examples and guidance align with the new `--create-spn` capability.

### Changes Made

1. **docs/end-to-end-setup-walkthrough.md**
   - Line 25: Added `--create-spn` to `prepare-cluster.sh` command in "First deployment" quick start
   - Line 43: Added `--create-spn` to `bootstrap.sh` command in "First deployment" quick start
   - Line 91: Added `--create-spn` to `prepare-cluster.sh` command in "Step 1: Prepare Your Cluster"
   - Line 161: Added `--create-spn` to `bootstrap.sh` command in "Step 2: Deploy the Application"

2. **README.md**
   - Line 117: Added `--create-spn` to `prepare-cluster.sh` command in "Operator fast path"
   - Line 125: Added `--create-spn` to `bootstrap.sh` command in "Operator fast path"
   - Lines 128–130: Added explanatory note: "`--create-spn` required only for first run; use when creating fresh SP or refreshing stale credentials"

3. **docs/radius-validation-checklist.md**
   - Line 11: Updated intro note to mention `--create-spn` for fresh SP provisioning and stale credential refresh

### Files Verified (No Changes Needed)
- `docs/phase-1-validation.md` — No bootstrap/prepare-cluster mentions
- `docs/phase-7-validation-checklist.md` — No bootstrap/prepare-cluster mentions
- `docs/phase-7-demo-walkthrough.md` — Mentions bootstrap context but no command examples needing update
- `docs/local-dev.md` — Local Kubernetes path; no bootstrap/prepare-cluster mentions

### Narrative Principle
Updated docs reflect the actual operator flow:
- **First deployment:** Both scripts use `--create-spn` (prepare-cluster may detect and create; bootstrap registers/refreshes with Radius)
- **Subsequent deployments:** `--create-spn` omitted (credentials already provisioned)
- **Credential refresh:** Add `--create-spn` to bootstrap if Azure creds go stale (e.g., expired secrets, revoked app registration)

### Learning
- Deployment script documentation must track when flags become functional. The `--create-spn` flag existed in help text but wasn't implemented for months; when it becomes real, examples need quick surgical updates to stay truthful.
- Command examples are truth claims. One stale example ("run without `--create-spn`") can cost operators 20 minutes of troubleshooting when credentials fail. Keep examples in sync with script capability.

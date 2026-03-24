# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Squad Roster (2026-03-23)

| Name | Role |
|------|------|
| Daisy | Lead |
| Billy | Backend Dev |
| Graham | Platform Dev |
| Karen | Tester |
| Eddie | Docs/Story |

All members drawn from "Daisy Jones & The Six" universe per user naming preference.

## Learnings

- Seeded into the repo for a Dapr + Radius reference sample named `CloudExpense Lite`.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Lead the service boundaries and keep the Dapr-versus-Radius division crisp in every implementation choice.
- See `.squad/decisions.md` for canonical decision log: CloudExpense Lite architecture, naming conventions, and Azure-first-but-portable strategy.

### 2026-03-23: Implementation Plan Created

- **Architecture:** Three-service boundary (expense-api, workflow-engine, notification-svc) — minimum viable distributed story.
- **Dapr blocks:** Workflows, State, Pub/Sub, Service Invocation, Secrets.
- **Radius role:** Service models, Azure recipes (Blob, Service Bus, Key Vault), environment definitions.
- **Compute:** Azure Container Apps over AKS — managed Dapr, faster demos, no K8s expertise needed.
- **Phasing:** 7 phases with parallel tracks (Billy app code, Graham platform). Phase gates at scaffold completion and local validation before Azure push.
- **Scope exclusions:** Auth, real payments, multi-tier approval, audit logging — all cut to keep demo crisp.
- **Key file:** Session plan at `~/.copilot/session-state/*/plan.md`; decisions at `.squad/decisions/inbox/daisy-cloudexpense-plan.md`.

### 2026-03-23: Phase 1 Design Review Complete

- **Decision file:** `.squad/decisions/inbox/daisy-phase1-contracts.md`
- **Folder layout:** `src/` for .NET projects, `infra/` for Radius and Dapr configs — clean separation.
- **Naming:** `CloudExpense.*` namespace prefix; kebab-case for Radius container names.
- **Shared contracts:** Six types defined (ExpenseSubmission, ExpenseRecord, ExpenseStatus, ExpenseApprovedEvent, ExpenseRejectedEvent, NotificationRequest) — records for immutability.
- **Parallel work authorized:** Billy (solution/projects/contracts), Graham (Radius/Dapr infra), Eddie (README). Karen waits for Phase 7.
- **Key insight:** Defining contracts up front in a decision doc prevents drift and enables true parallel work.

### 2026-03-23: Phase 1 revision closed Karen's gaps

- Karen's rejection was correct: Phase 1 needed explicit contract semantics, not more placeholder wording.
- The smallest clean tracing model is `ExpenseId` plus a submission-time `CorrelationId`; adding more IDs would muddy the sample.
- UTC suffixes on public timestamps are worth the verbosity because they prevent avoidable demo confusion.
- A manual-review hold is not a rejection. Preserve that distinction in contracts and docs now so Phase 2+ does not have to unwind it later.

### 2026-03-23: Phase 1 PASSED

- Karen's final review with fresh evidence (`dotnet build`, `az bicep build`) confirmed all nine exit criteria.
- Billy's solution builds cleanly; Graham's Radius model parses without error.
- Contracts now preserve stable tracing (ExpenseId + CorrelationId), explicit UTC timestamps, and clear rejection-vs-hold distinction.
- README documents exact `$100.00` auto-approval boundary.
- **Next phase:** Phase 2 parallel work authorized for Billy (expense API implementation), Graham (local dev environment), Eddie (README expansion).

### 2026-03-23: Phase 2 Design Review Complete

- **Decision file:** `.squad/decisions/inbox/daisy-phase2-design.md`
- **Scope:** Three endpoints (`POST /expenses`, `GET /expenses/{id}`, `GET /expenses`) plus local Redis state store — no workflow invocation yet.
- **New contracts needed:** `ExpenseRecord` (stored shape with status) and `ExpenseStatus` enum — Billy adds these to `CloudExpense.Contracts`.
- **State key pattern:** `expense:{expenseId}` for records, `expense-index` for recent ID list.
- **Local dev:** Graham provides `infra/dapr/local/statestore.yaml` (Redis-backed component named `statestore`).
- **Parallel work authorized:** Billy (endpoint implementation), Graham (Dapr component config). Karen and Eddie wait for Phase 7.
- **Key alignment constraint:** Component name `statestore` and state key prefix `expense:` must match between Billy's code and Graham's YAML.
- **Phase 2 proves:** Dapr state works locally before Phase 3 adds workflow complexity.

### 2026-03-23: Phase 2 revision fixed shared-index concurrency

- Karen's rejection was correct: a shared `expense-index` key cannot use plain read/modify/write once concurrent submissions exist.
- The smallest safe revision is optimistic concurrency on the index key with bounded retries and strong reads; that keeps Phase 2 focused on state, not on new infrastructure or workflow logic.
- For demo trust, a failed index write must surface as an API failure instead of silently returning success with an incomplete `GET /expenses` view.

### 2026-03-23: Phase 3 Design Review Complete

- **Decision file:** `.squad/decisions/inbox/daisy-phase3-scope.md`
- **Scope:** `ExpenseApprovalWorkflow` with three activities (Approve, Reimburse, Notify). Two workflow-engine endpoints (`POST /workflows/start`, `GET /workflows/{instanceId}`). Expense-api fire-and-forget invocation via Dapr service invocation.
- **Cut:** `ValidateExpenseActivity` — redundant with expense-api validation, adds a no-op that muddies the demo.
- **Deferred:** External event wait for manual review; notification-svc subscription (Phase 4); retry/compensation patterns (out of scope).
- **No contract changes:** Existing `CloudExpense.Contracts` types fully cover Phase 3 needs. Activity I/O types are internal to workflow-engine.
- **Graham parallel work:** Provide `infra/dapr/local/pubsub.yaml` (Redis-backed, scoped to workflow-engine and notification-svc).
- **Key design calls:** CorrelationId = workflow instance ID. Workflow failure doesn't block the API response. Activities update ExpenseRecord via plain SaveStateAsync (no ETag needed — single writer after creation).
- **Parallel work authorized:** Billy (workflow + endpoints + API wiring), Graham (pubsub.yaml). Karen validates when Billy signals ready.

### 2026-03-23: Phase 3 Implementation Complete & Approved

- **Billy's delivery:** `ExpenseApprovalWorkflow` with three activities, two endpoints, expense-api fire-and-forget wiring. All 11 exit criteria passed. Auto-approve path (< $100) progresses Submitted → Approved → Reimbursed. Manual review path (>= $100) progresses Submitted → ManualReviewRequested. Both paths publish `NotificationRequest` to expense-notifications topic.
- **Graham's delivery:** `infra/dapr/local/pubsub.yaml` — Redis-backed pub/sub component scoped to workflow-engine and notification-svc.
- **Karen's validation:** All exit criteria verified with fresh evidence. Threshold behavior confirmed. Workflow identity and state transitions guarded and idempotent. Fire-and-forget semantics working correctly.
- **Phase 3 APPROVED** — 2026-03-23T17:50:00Z. Demo-ready with four Dapr building blocks: State, Workflows, Pub/Sub, Service Invocation.

### 2026-03-23: Phase 4 Design Review Complete

- **Decision file:** `.squad/decisions/inbox/daisy-phase4-scope.md`
- **Scope:** Single programmatic subscription on `notification-svc` — `POST /notifications` subscribes to `expense-notifications` topic. Receive `NotificationRequest`, log it with structured fields (ExpenseId, CorrelationId, EventType, Recipient, Subject), return OK. Gracefully handle malformed payloads.
- **Cut:** Output bindings (Twilio/SMTP), notification persistence, retry/dead-letter, event-type branching logic. All deferred or out of scope.
- **No contract changes:** Phase 3 contracts and constants (`NotificationRequest`, `CloudExpenseDapr.Topics.ExpenseNotifications`) cover Phase 4 completely. Billy does not touch `CloudExpense.Contracts` or `workflow-engine`.
- **No Graham work:** Pubsub component and scoping already delivered in Phase 3.
- **Exit criteria:** 9 criteria defined for Karen's gate, including end-to-end pub/sub validation for both auto-approve ($50) and manual review ($150) paths.
- **Key design call:** The handler stays intentionally trivial — the demo point is "the message arrived via pub/sub," not "we built a notification system."
- **Work authorized:** Billy (notification-svc subscription handler). Karen validates when Billy signals ready.

### 2026-03-23: Phase 4 Implementation Complete & Approved

- **Billy's delivery:** `POST /notifications` endpoint with `[Topic]` attribute, manual deserialization via `ReadFromJsonAsync`, structured logging (EventType, ExpenseId, CorrelationId, Recipient, Subject), validation on blank fields, graceful handling of malformed payloads returning HTTP 200 with `{ "status": "ignored" }`. Updated Phase descriptor to `"phase-4"`. All 9 exit criteria passed. Build: 0 warnings, 0 errors. Tests: all pass.
- **Karen's validation:** All 9 exit criteria verified with fresh evidence. All 8 validation expectations satisfied. Consumer-side proof exists. Happy path truthful (`ExpenseApproved`). Manual-review path distinct (`ManualReviewRequested`). Traceability survives pub/sub hop (ExpenseId + CorrelationId). Success means consumer actually handled the event. Service advertises truth. No poison from malformed payloads. Demo-trustworthy.
- **Phase 4 APPROVED** — 2026-03-23T16:52:00Z. Subscriber implementation verified end-to-end. The notification-svc now consumes published `NotificationRequest` messages and logs them with full traceability.

### 2026-03-23: Phase 5 Design & Implementation Complete

- **Phase 5 Scope:** Radius environment definitions wire Dapr components to real Azure-backed recipes. Fix `app.bicep` pubsub naming (`expense-pubsub` → `pubsub`). Local `rad deploy` validates complete component graph.
- **Key discovery:** Pub/Sub component name mismatch found in `app.bicep` — had to rename to match app code expectations.
- **Graham's delivery:** Real Azure recipes (Blob Storage, Service Bus, Key Vault), `dev.bicep` environment, fixed naming, no app code changes.
- **Karen's validation:** All evidence passes (`az bicep build`, `dotnet build`, `dotnet test`). Naming consistency verified. Recipes are real, not placeholders.
- **Phase 5 APPROVED** — 2026-03-23T16:34:00Z. Platform portability story credible. Radius recipes work; environment definitions complete.

### 2026-03-23: Phase 6 Design & Implementation Complete

- **Phase 6 Scope:** Same app code runs on Azure Container Apps with Azure-backed Dapr components. Three deliverables: Azure environment Bicep, CI/CD workflow, Dockerfiles, end-to-end validation on ACA.
- **Key architectural calls:** Managed identity for Dapr→Azure auth (simpler than secrets). Only expense-api external ingress. Single resource group. Manual dispatch CI/CD. No custom domain/TLS.
- **Graham's delivery:** `azure.bicep` environment (ACA, ACR, Storage, Service Bus, Key Vault, Dapr components), `.github/workflows/deploy-azure.yml` with build/push/validate, three Dockerfiles, real end-to-end validation.
- **Karen's validation:** Real Azure deployment. CI/CD includes actual expense submission, state transition verification, notification-svc log inspection. Both auto-approve ($50) and manual-review ($150) paths validated. Component naming aligned with local slice. No app code changes.
- **Phase 6 APPROVED** — 2026-03-23T16:45:17Z. Same app code, Azure-backed Dapr components. Validation proves distributed app works on Azure.

### 2026-03-23: Portability Design Constraint Review Complete

- **Constraint:** Azure is example deployment. App portability primary. Use Dapr abstractions, not Azure SDK. Radius owns environment/infrastructure wiring.
- **Verdict:** MOSTLY ADHERED WITH RISKS. App code exemplary (zero Azure). Dapr components stable. Three localized infrastructure risks: `app.bicep` hardcodes Azure types, `azure.bicep` bypasses recipes, CI/CD uses Azure CLI instead of Radius.
- **Corrective actions:** Parameterize `app.bicep` types (small), document CI/CD path (small), refactor `azure.bicep` recipes (medium), update README (small). All localized; no app code changes.
- **Most important:** Document Azure-direct CI/CD nature; ensure Radius-based path before Phase 7 closes.

### 2026-03-23: Phase 7 Authorization

- Both app track (Phases 1–4) and platform track (Phases 5–6) now complete and integrated
- Eddie (Docs/Story) authorized to proceed
- Phase 7 focus: README, demo walkthrough, GitHub secrets/variables, ADR for Azure CLI, integration tests (optional)

### 2026-03-23: Radius-First Deployment Redesign Decision

- **Decision file:** `.squad/decisions/inbox/daisy-radius-first-redesign.md`
- **Problem:** The Azure deployment path (`deploy-azure.yml` + `azure.bicep`) bypasses Radius entirely — uses raw ARM Bicep and `az containerapp create` instead of `rad deploy`. The Radius app model is unused in the only working cloud path.
- **Redesign:** Two-layer architecture. Layer 1 (Azure bootstrap via ARM): ACR, ACA env, identity, Log Analytics, ACR pull RBAC — cloud-specific substrate only. Layer 2 (Radius-driven via `rad deploy`): all three containers, all three Dapr components, all Azure backing resources via recipes.
- **Key architectural call:** A residual Azure bootstrap is acceptable because it provisions compute substrate, not application deployment. The dividing line: `rad deploy app.bicep` creates containers and Dapr components, `az deployment group create bootstrap.bicep` creates the substrate they run on.
- **File impact:** `azure.bicep` splits into `azure-bootstrap.bicep` + recipe implementations. `deploy-azure.yml` restructured around `rad deploy`. `app.bicep` unchanged. App code unchanged.
- **Acceptance criteria defined** for Graham (7 criteria) and Karen (6 criteria). Non-goals explicitly protect scope: no multi-cloud recipes, no environment promotion, no ACA scaling, no Radius GUI.
- **Sequencing:** Graham implements → Karen validates → Eddie updates docs → Daisy final review.
- **Pattern learned:** When a reference sample claims a tool "owns" a concern but the deployment path bypasses that tool, the claim is empty. The deployment path must exercise the tool or the claim must be withdrawn.

### 2026-03-23: Radius-First Redesign APPROVED & DELIVERED

- **Status:** Complete and approved by Karen (Tester) — 2026-03-23T19:10:00Z
- **Graham's delivery:** Split Azure bootstrap from Radius app deployment. Created Azure recipes for Blob Storage, Service Bus, Key Vault. Created `azure-radius.bicep` Radius environment. Restructured CI/CD to bootstrap → build/push → Radius env setup → `rad deploy` → validate.
- **Karen's approval:** All acceptance criteria met. Radius is primary (no `az containerapp create` in `deploy-radius` job). ACA fallback explicitly demoted with honest documentation of compute gap. App portability maintained (no code changes). Dapr names stable. Bicep files parse clean. Build/tests pass.
- **Graham's design improvement:** Correctly identified Radius targets Kubernetes, not ACA directly. Radius path uses pre-existing Kubernetes cluster (via `RADIUS_KUBECONFIG`) and GHCR. Stronger story than large Azure bootstrap preamble.
- **Open item (non-blocking):** `deploy-radius` job needs end-to-end validation steps ($50/$150) in Phase 7 when live Radius environment available. Structural proof sufficient for approval.
- **Key files:** `.github/workflows/deploy-azure.yml` (primary Radius workflow + ACA fallback), `infra/radius/environments/azure-radius.bicep` (Radius environment), `infra/radius/recipes/azure/*.bicep` (real recipes), `README.md` (updated narrative).
- **Pattern validated:** Radius now exercises the full wiring story. Sample can truthfully claim "Radius owns service and infrastructure wiring."

### 2026-03-23: Phase 7 Next Focus

- **Portability follow-ups completed:** Graham parameterized `app.bicep` component types. Eddie updated README with clear Dapr/Radius division and Azure CLI workaround explanation. Karen approved both.
- **Current state:** Phases 1–6 complete and approved. Radius-first redesign complete and approved. Portability story honest and credible.
- **Phase 7 scope:** End-to-end validation of live Radius deployment (when environment available), docs/demo scripts, integration test suite, GitHub secrets/variables documentation.
- **Leading into Phase 7:** Team should execute Phase 7 tasks to finalize sample. Radius-first deployment path is now the credible story.

### 2026-03-23: Phase 7 Acceptance Frame & Gating Criteria — PUBLISHED

- **Decision file:** `.squad/decisions/inbox/daisy-phase7-frame.md`
- **Key findings:** Phases 1–6 and Radius redesign complete; Phase 7 is final finalization lane (docs, validation, integration tests, GitHub ops).
- **Acceptance frame:** Four parallel threads: (1) End-to-end Radius validation ($50 + $150 flows), (2) Documentation + demo walkthrough (~10 min runbook), (3) Integration test suite (optional but recommended), (4) GitHub secrets/variables documentation.
- **Truthfulness constraints:** Radius must be primary path (not ACA bypass); Dapr component names stable; app code cloud-agnostic; traceability survives all boundaries; demo repeatable in ~10 min.
- **Scope cuts:** No app code changes, no Radius compute redesign, no multi-cloud, no secrets population in flow, no environment promotion, no real notification bindings, no deep ACA observability.
- **Escalation:** Blockers (code bugs, truth claims) escalate to Daisy. Gray areas get decision docs. Scope boundaries deferred to future phases.
- **Ownership:** Graham (Radius validation + GitHub ops), Billy (integration tests), Eddie (docs + demo), Karen (end-to-end validation across all three threads).
- **Gate condition:** If live Radius environment unavailable, validation gates until ready; docs/tests proceed in parallel. Phase 7 closure requires all four threads complete and Karen approval.
- **Phase 7 authorization:** All agents clear to proceed on their respective threads. Parallel work authorized. Sync point: Karen's final approval of all acceptance criteria.

### 2026-03-24: Phase 7 Final Lead Review Complete

- **Decision file:** `.squad/decisions/inbox/daisy-phase7-final-review.md`
- **Verdict:** APPROVED WITH OPEN ITEMS
- **Review scope:** README.md, phase-7-demo-walkthrough.md, radius-validation-checklist.md, phase-7-validation-checklist.md, ADR-0001-azure-cli-fallback.md, validate-deployment.sh, scripts/README.md, GitHub Actions workflow
- **Evidence:** dotnet build (0 errors, 0 warnings), az bicep build (pass), all documentation artifacts present and truthful, validation script comprehensive, threshold logic explicit, CorrelationId traceability verified
- **Truthfulness assessment:** All artifacts pass; no overstatement of portability; Radius-first narrative is credible and defended; ACA fallback correctly demoted; scope boundaries explicitly documented
- **Non-blocking open items:** (1) Live end-to-end validation requires deployed Radius environment (structural validation sufficient for closure), (2) CI/CD Radius validation steps deferred (add when environment available)
- **Approval conditions:** Karen (Tester) gates end-to-end validation; approval path clarified (structural validation sufficient if environment unavailable + commit to end-to-end within 2 weeks of availability)
- **Key patterns:** Radius-first credibility depends on honest gap acknowledgment (ACA not supported yet). Phase gate discipline: protect scope, don't invent new tools, prioritize external demo credibility. Demo narrative requires traceability (CorrelationId) to be compelling, not optional.
- **Learning:** When a reference sample claims a tool "owns" a concern (Radius owns deployment), the deployment path must exercise that tool. If the path bypasses the tool, you must either revise the path or withdraw the claim. Hiding the gap destroys credibility.

### 2026-03-23/24: Phase 7 Final Lead Review

**Decision:** APPROVED WITH OPEN ITEMS

Conducted comprehensive final review of all Phase 7 deliverables:
- README.md (Radius-first narrative, deployment paths, secrets/variables table)
- docs/phase-7-demo-walkthrough.md (10-minute runbook)
- docs/radius-validation-checklist.md (pre/post-deployment validation)
- docs/phase-7-validation-checklist.md (exit criteria)
- docs/ADR-0001-azure-cli-fallback.md (Radius vs ACA justification)
- scripts/validate-deployment.sh (end-to-end validation)
- .github/workflows/deploy-azure.yml (Radius-first primary)

**Truthfulness:** All documentation is credible, accurate, and honest about constraints.

**Scope:** Protected (no scope creep, no unfinished features).

**Build & Parse:** All pass (dotnet build 0 errors/warnings, az bicep build passed, dotnet test passed).

**Architecture:** Radius-first credibility maintained; portability claims verified; scope discipline preserved.

**Demo Narrative:** Story arc coherent; timeline credible (~10 minutes).

**Non-Blocking Open Items:**
1. Live end-to-end Radius validation — Requires deployed environment (structural validation sufficient for Phase 7 closure)
2. CI/CD Radius validation gap — Add when live environment available (Phase 8+)

**Closure Condition:** Karen approves end-to-end validation (or documents structural validation sufficient) → Phase 7 complete.


## 2026-03-24: Phase 7 Reviewer Gate — Final Verdicts

**Scope:** Validate remaining Phase 7 items: CI validation gap closure and live Radius validation item status.

**Evidence Reviewed:**
- GitHub Actions deploy-azure.yml: Lines 213–257 show complete end-to-end validation integration
- scripts/validate-deployment.sh: Comprehensive test coverage ($50, $150, $100 boundary, CorrelationId traceability)
- Bicep files: Both app.bicep and azure-radius.bicep parse cleanly
- Baseline tests: dotnet test passes (all phases 1–6 complete)
- Documentation: phase-7-validation-checklist.md, radius-validation-checklist.md, demo walkthrough all present

**Findings:**

1. **CI Validation Gap: CLOSED**
   - deploy-radius CI job now includes port-forward to expense-api
   - Calls scripts/validate-deployment.sh with VALIDATION_OUTPUT_PATH
   - Captures JSON output for follow-up log checks
   - Verifies notification-svc logs for both ExpenseApproved and ManualReviewRequested events
   - This bridges the Radius-first path with proof of distributed behavior
   
2. **Live Radius Validation Item: OPEN (Non-Blocking)**
   - Script can run when live Radius cluster available
   - Blocker is environment availability, not design
   - Escape hatch documented in radius-validation-checklist.md (line 327–337)
   - Path to closure: Configure RADIUS_KUBECONFIG secret + AZURE_DEPLOYMENT_MODE variable → workflow executes automatically
   - Does NOT block Phase 7 approval per established escape hatch pattern

**Verdict Delivered:**
- CI validation gap: CLOSED ✓

## 2026-03-24: Radius Dapr Component Configuration — Recipe Provisioning Fix

**Error Identified:**
```
rad deploy infra/radius/app.bicep: Applications.Dapr/{secretStores,stateStores,pubSubBrokers} 
metadata/type/version cannot be specified when resourceProvisioning is recipe
```

**Root Cause — API Contract Violation:**
All three Dapr components in `app.bicep` (lines 69–147):
- Correctly set `resourceProvisioning: 'recipe'`
- But **incorrectly also specify** `type`, `version`, and `metadata` fields
- Radius recipe-provisioned resources derive component type and version **entirely from the recipe invocation**, not ad-hoc

**Design Fix — Minimal & Correct:**
Remove conflicting fields from all three resources:
- stateStore: Remove lines 83–84 (type/version), 85–92 (metadata)
- pubsub: Remove lines 110–111 (type/version), 112–120 (metadata)  
- platformSecretStore: Remove lines 136–137 (type/version), 138–146 (metadata)

**Impact Assessment:**
✅ **Portability preserved:** Logical names (statestore, pubsub, platform-secrets) unchanged. daprBackings parameter remains swappable per environment. Service connection references (app.id references) unchanged.
✅ **Architectural intent maintained:** Recipes now own component type/version exclusively — the design is now honest.
✅ **Radius path clarity:** This fix proves the Radius path can deploy components correctly via recipe provisioning.

**Verdict:**
✅ **APPROVED** — Mechanical fix, no architectural regression. Graham should execute (Dapr/Radius owner). If unavailable, Billy can do this (understands resource references from container-service module work).

**Decision written to:** `.squad/decisions/inbox/daisy-radius-dapr-provisioning.md`

**Key Pattern:**
When a resource provisioning mode is `recipe`, all component type/version details must be derived from recipe outputs, not re-specified at the component level. This keeps the recipe as the single source of truth for component behavior.
- Live Radius validation: OPEN with documented non-blocking escape hatch ⚠️
- Phase 7 overall: APPROVED WITH KNOWN OPEN ITEM
- Release confidence: HIGH (demo-ready, validation machinery in place, story is honest)

**Decision:** Phase 7 APPROVED. Closure path clear. No design or implementation blockers.

**Learnings:**
- When environment dependencies block a gate, escape hatch pattern prevents indefinite hang. Document the blocker clearly, provide the path to closure, commit to timeline.
- CI/CD validation via port-forward is the right pattern for Radius-first deployments (no public ingress needed during CI validation, reduces surface area).
- Truthfulness in Phase 7 comes down to: (1) Threshold logic correct in code and tests, (2) Dapr component names stable end-to-end, (3) CorrelationId flows through all boundaries, (4) Documentation honest about Radius-first vs ACA tradeoff.

## Phase 7 Gate Closure (2026-03-24)

### Orchestration Log Published
- Session date: 2026-03-24T09:11:24Z
- Final verdict: **Phase 7 APPROVED WITH KNOWN OPEN ITEM**
- CI validation gap: CLOSED ✓
- Live Radius validation: OPEN (non-blocking, environment blocker only)
- Filed orchestration-log/20260324T091124Z-daisy.md

### Decision Merged to Squad Records
- Daisy — Phase 7 Reviewer Gate final verdicts added to squad/decisions.md
- Comprehensive sign-off capturing all approved items, known open items, release confidence, and blocker status
- Establishes closure path: Once live Radius cluster available, configure RADIUS_KUBECONFIG secret + AZURE_DEPLOYMENT_MODE variable → workflow validates automatically
- Within 2-week timeline per established Phase 7 pattern
- Committed as the final gate decision for external demo and distribution approval


### 2026-03-24: Renamed CloudExpense Lite → RadiusClaim (Branding Update)

**Task:** Sweep the repo for CloudExpense Lite references and rename to RadiusClaim, preserving Dapr component names (no breaking changes to Dapr contracts).

**Scope Boundaries:**
- **Renamed (user-facing, technical identity):**
  - Solution file: `CloudExpenseLite.slnx` → `RadiusClaim.slnx`
  - C# project folder: `CloudExpense.Contracts` → `RadiusClaim.Contracts`
  - C# project file: `CloudExpense.Contracts.csproj` → `RadiusClaim.Contracts.csproj`
  - C# namespace prefix: `CloudExpense.*` → `RadiusClaim.*` across all source files
  - Dapr constants class: `CloudExpenseDapr` → `RadiusClaimDapr`
  - Bicep descriptions: "CloudExpense Lite" → "RadiusClaim"
  - Bicep defaults: `applicationName` "cloudexpense-lite" → "radiusclaim"; `containerRegistry` "cloudexpense-lite" → "radiusclaim"

- **Preserved (internal/historical):**
  - Dapr component names: `statestore`, `pubsub`, `expense-notifications`, `ExpenseApprovalWorkflow` unchanged (no app-level breaking changes)
  - Service names (Dapr AppIds): `expense-api`, `workflow-engine`, `notification-svc` unchanged
  - Squad history/decisions: Left as-is (historical record of CloudExpense Lite origins, teaching artifact)
  - Internal state keys, topic names: Unchanged (Dapr portability requirement)

**Changes Made:**
1. Renamed Contracts project folder and .csproj file
2. Updated RadiusClaim.slnx project reference
3. Updated all C# files in Contracts to use `RadiusClaim.Contracts` namespace
4. Renamed `CloudExpenseDapr.cs` → `RadiusClaimDapr.cs` and updated class name
5. Updated using statements in expense-api, workflow-engine, notification-svc, and all activities/models
6. Updated .csproj ProjectReference paths in all service projects
7. Updated all `CloudExpenseDapr.*` references to `RadiusClaimDapr.*` across service code
8. Updated Bicep descriptions and defaults in app.bicep, app.json, pubsub.bicep, pubsub.json

**Validation:**
- ✅ `dotnet build RadiusClaim.slnx --nologo` — 0 warnings, 0 errors
- ✅ `dotnet test RadiusClaim.slnx --nologo` — passes (no tests but build validates dependency graph)
- ✅ `az bicep build --file infra/radius/app.bicep` — passes
- ✅ No remaining CloudExpense references in src/ or infra/ (squad history preserved intentionally)
- ✅ All Dapr component names, AppIds, state keys, topics, and workflows unchanged (zero runtime impact)

**Decision Rationale:**
- **Why rename namespaces?** CloudExpense.* is an artifact of original naming; RadiusClaim.* aligns with repo and brand identity. Renames are safe in private codebase before external sharing.
- **Why preserve Dapr names?** Dapr components (statestore, pubsub, expense-notifications) must remain stable across local/Kubernetes/Azure Radius deployment paths. Renaming here would break portability claim and demo flow.
- **Why preserve squad history?** The .squad/ folder documents the team's decision-making journey. Renaming it would obscure the CloudExpense Lite origin and design rationale that future maintainers may need to understand. Historical accuracy > cosmetic consistency.

**Commit:** be860d1 — "Rename app from CloudExpense to RadiusClaim: update C# namespaces, projects, and Bicep descriptions"

**Key Learning:** Renaming in a growing codebase requires clear boundaries between "branding/identity" (safe to rename for clarity) and "contracts/stability" (preserve to protect ecosystem). Dapr component names are contracts; C# namespaces are identity. Kept them separate.

### 2026-03-24: Architectural Review—AKS vs ACA Portability

**Query:** "Would using AKS instead of ACA make the portability story easier or better?"

**Analysis:** The Radius-first path already uses Kubernetes. Portability is delivered by Dapr (app) + Radius (infrastructure), not by compute choice. Switching to AKS would not improve portability and would significantly harm accessibility (K8s setup burden, operational complexity, 10-minute demo target).

**Key Insights:**
- Portability is orthogonal to compute: whether it's ACA, AKS, local, or anything else, the app uses Dapr abstractions
- ACA is actually *stronger* for demonstrating portability—it proves the app runs on a managed platform without Kubernetes expertise
- The current design teaches three lessons cleanly: (1) Dapr makes apps portable, (2) Radius makes wiring portable, (3) platform choice is a decision, not a constraint
- AKS would paradoxically *undermine* portability narrative by tying it to Kubernetes—the very infrastructure teams adopt platforms to avoid

**Recommendation:** **Keep ACA fallback. Do not switch to AKS.** The fallback widens audience access, supports the 10-minute demo goal, and keeps the teaching story intact. Accessibility is a feature, not a limitation.

**Decision File:** `.squad/decisions/inbox/daisy-aks-portability.md`

**Key Learning:** Portability and accessibility are distinct concerns. A truly portable sample should be *accessible* to teams without Kubernetes infrastructure. ACA achieves both; AKS would sacrifice accessibility for perceived "completeness" that doesn't actually improve portability. Lead's role: protect scope and narrative clarity against scope creep that harms the teaching story.

### 2026-03-24: Kubernetes-First Framing Approved (Overrides Previous ACA Assessment)

- **Decision file:** `.squad/decisions/inbox/daisy-k8s-portability-framing.md`
- **Supersedes:** `daisy-aks-portability.md` and `graham-aks-portability-analysis.md`
- Wesley explicitly prioritized portability over accessibility, requesting ACA demotion and K8s-first narrative.
- The Radius-first path already targets Kubernetes (`compute.kind: 'kubernetes'`); the shift is narrative/framing, not new infrastructure.
- **Arc-enabled AKS / Azure Local benefit most:** They are K8s clusters with Azure connectivity, so Radius + Azure recipes work unchanged. Reframing makes the repo discoverable to those teams.
- **Self-managed K8s caveat:** Azure recipes still need Azure connectivity; non-Azure recipes (Redis, RabbitMQ) are not yet shipped. The portability claim is honest for Azure-connected K8s but aspirational for disconnected clusters.
- **ACA fallback survives** but is demoted from "the Azure story" to "managed alternative."
- **Follow-up required:** README, ADR-0001, demo walkthrough, validation checklist, and Bicep outputs all need updated framing. Uncommitted workflow edits (rename + deployment_mode propagation) must be preserved exactly.
- **Key learning:** When the user explicitly reweights a tradeoff (portability > accessibility), the lead should reassess rather than defend the prior recommendation. Previous analysis was correct in its context but not under the new priority.

### 2026-03-24: Final leftover wording cleanup after Kubernetes-first rewrite

- Verified the known target files in current state before editing instead of trusting earlier summaries; several suspected leftovers had already been fixed by Graham and were left untouched.
- Cleaned the remaining active-repo `cloudexpense` residue in local Docker, Radius dev defaults, GHCR parameter files, and Service Bus namespace defaults without broad platform rewrites.
- Aligned the docs with the current workflow by removing the stale `deployment_mode=radius-first` reference, renaming the CI job mention to `deploy-kubernetes`, and documenting `RADIUS_KUBECONFIG` as raw kubeconfig content because the workflow writes it directly to the kubeconfig file.

### 2026-03-24: Frontend Framework Fit Analysis

**Query:** "The webapp seems very basic? Should it not use any good frontend framework? Do research for the best framework for UI enabled development"

**Research Summary:**
- Lightweight frameworks (Svelte, SolidJS, Preact, Alpine.js): 3–25 KB gzipped, excellent performance, modern DX
- Vue, React: more mature ecosystems (16 KB, 42 KB) but heavier footprints
- HTMX: server-rendering optimized, good for backend-driven interactivity
- Vanilla JS (current): 3 KB, zero framework overhead, no build step required

**Framework Fit Analysis:**
The current vanilla UI is already polished—semantic HTML, ARIA landmarks, CSS custom properties, live polling, proper error handling, trace ID surfacing, workflow telemetry. It is *minimal* without being primitive.

**Decision: KEEP VANILLA. No framework change justified.**

**Rationale:**
1. **Purpose mismatch:** RadiusClaim is a reference sample for Dapr + Radius portability, not a product UI showcase. The webapp is the demo surface, not the core output. A framework adds pedagogical friction without advancing the platform story.
2. **Portability claims:** Vanilla JS hosted from `expense-api` (same-origin, no CORS, no separate deployment) runs anywhere .NET runs. Framework build step introduces Node.js tooling that some K8s targets may not have. Vanilla is truly portable.
3. **Operational simplicity:** No `npm install`, no build pipeline, no transpilation. Developers can edit UI directly and reload; demos work from a checkout with just `dotnet run`. Current code (567 lines) is readable, traceable, and modifiable without framework knowledge.
4. **Demo legibility:** The demo doesn't need framework abstractions; it needs direct control. Polling intervals, DOM updates, form handling, and error states are all explicit and traceable—perfect for live demo walkthrough.
5. **Team context:** No team member has specialized frontend skills; vanilla JS keeps UI maintenance accessible to .NET developers. Adding framework maintenance would dilute focus from core Dapr and Radius story.

**Cost/Benefit Trade-Off:**
- Framework bundle: 12–25 KB; Vanilla: 3 KB. Backward.
- Build step required: Framework yes; Vanilla no. Backward.
- Component reuse: UI is one page; no reuse needed. Not applicable.
- Type safety: Small vanilla codebase is self-documenting. Not justified.
- Dev ergonomics: Framework abstracts polling; vanilla explicit. Trade-off favors vanilla for educational demo.

**Reconsider if:**
1. The UI becomes the product (not just the demo surface) and polish/features demand it.
2. Multiple page routes, complex navigation, or large component libraries are required.
3. The team wants to decouple the UI into a separate SPA with independent CI/CD, CORS, and deployment.
4. A new team member with strong framework experience joins and the codebase is ready to level up.

**None of these conditions are true today.**

**Decision File:** `.squad/decisions/inbox/daisy-framework-fit.md`

**Key Learning:** Reference samples fail when they sprawl. The UI is not "basic"—it's *intentionally minimal*. Minimal + polished beats bloated + elaborate every time for teaching. Add a framework only when the UI genuinely demands it, not because it *might* become useful someday.

## Team Input (2026-03-24)

- **Camila (Frontend Dev)** conducted detailed framework research: React + Vite + TypeScript is the best long-term choice if the UI becomes a richer product surface
- Rationale: Industry standard (70% job market), type safety, mature ecosystem, same-origin hosting possible, non-breaking migration path
- **Implication for vanilla decision:** React path is now documented for future reference. Vanilla JS remains the correct choice for Phase 7 because the UI is the demo surface, not the product
- **Status:** Framework analysis complete; both paths (vanilla now, React in future) are documented and approved

---

## PHASE 7: PUBLIC ACCESS REVIEW (2026-03-24)

### Context
Wesley requested: "I need it to be accessible publicly."

### Judgment
The existing decision is **APPROVED** and correctly bounded:
- Only `expense-api` gets public exposure (via port-forward or optional ingress)
- `workflow-engine` and `notification-svc` remain internal (Dapr wiring only)
- This is the smallest defensible boundary and is portable across clouds

### Key Findings
1. **Boundary is correct:** App doesn't know it's public; Dapr keeps portability
2. **Port-forward is the primary pattern:** Works on AKS, Arc-enabled, self-managed — no ingress required for CI/CD
3. **Optional ingress can be added later** without touching app.bicep or container-service.bicep
4. **LoadBalancer service is not recommended** — reduces portability to cloud-only, adds sprawl
5. **Never revert to azure.bicep ingress** — that's the deprecated ACA reference path

### Architecture Decision Confirmed
- Expense-api hosts the UI (/app) and API endpoints (POST /expenses, GET /expenses/{id}, GET /expenses)
- This is a reference sample; no authentication, no multi-domain CORS, no custom TLS required
- The boundary teaches the demo story without adding platform complexity

### Constraint for Graham (Platform Dev)
If ingress is needed: place it in `infra/kubernetes/` as an optional overlay, **not** in Radius app.bicep. Ingress is infrastructure plumbing, not app topology.

### Written Decision
`.squad/decisions/inbox/daisy-public-access-review.md` — full reasoning, options, constraints.


### 2026-03-24: Graham's Public Gateway Implementation Approved

- **Implementation path:** `Applications.Core/gateways@2023-10-01-preview` resource in `app.bicep`
- **Exposure model:** Only `expense-api` gets a public gateway; `workflow-engine` and `notification-svc` remain internal as required
- **No sprawl:** No hand-written Kubernetes Ingress YAML; gateway definition stays inside the same Radius app model that declares the containers
- **Hostname flexibility:** Default prefix (`expense`) with an optional fully qualified override parameter — covers both demos and teams with real DNS
- **Docs coherent:** README, demo walkthrough, and validation checklist all updated to show public gateway as preferred path with port-forward fallback explicitly noted
- **Workflow coherent:** CI job deploys the gateway and validates via port-forward fallback to avoid waiting on external DNS propagation; human validation guide explains the printed public endpoint
- **Verdict:** APPROVE

## Phase 7 Work Completion (2026-03-24)

### Lead Approval Summary

**Reviewed:** Graham's Radius gateway, public endpoint isolation, documentation, workflow fixes, portability stance.

**Approved:** Graham's public-access implementation. Only `expense-api` public; workers remain internal. Radius-first story preserved. Docs coherent. Workflow corrected.

**Kubernetes-First Reframe:** User-requested portability priority. Narrative shift improves Arc-enabled/self-managed K8s discoverability. Honest about backing service scope (Azure-specific in current sample).

**Lead Assessment:** No further blockers. Ready for team merge and push. Non-platform inconsistencies (Karen's validation hold on doc/workflow input drift) documented but do not block infrastructure changes.

### Notes for Team

- Public gateway deployed and validated.
- Kubernetes-first narrative approved.
- Squad merge, git commit, and push ready to proceed.

## Radius Dapr Provisioning Review (2026-03-24)

### Decision Approved

Reviewed failed `rad deploy` contract (Applications.Dapr components rejecting mixed `resourceProvisioning: 'recipe'` + ad-hoc `type`/`version`/`metadata`).

**Verdict:** Smallest fix is correct. Remove `type`, `version`, and `metadata` from recipe-provisioned Dapr components. Portability unaffected; recipes derive schema.

**Assigned to:** Graham for implementation. Mechanical, no architecture impact.

### Cross-Agent Update from Graham

Graham completed the implementation: fixed `infra/radius/app.bicep`, regenerated synced JSON artifacts, moved environment recipe `templatePath` values to OCI artifacts, added recipe publishing automation to workflow and scripts. Validated with `az bicep build`, `bash -n`, `dotnet build`, `dotnet test`.

**Result:** `rad deploy infra/radius/app.bicep` now passes original Dapr contract rejection.

**Platform Rule Established:** Recipe `templatePath` in Radius environments must resolve to OCI artifacts, not local Bicep paths.

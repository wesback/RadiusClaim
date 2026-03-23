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

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

## Phase 3 Work (2026-03-23)

### Delivered

**Phase 3 Workflow Implementation**
- Implemented `ExpenseApprovalWorkflow` with branching logic for auto-approve (< $100) and manual review (>= $100) paths
- Created three activities:
  - `ApproveExpenseActivity` — evaluates amount, sets status to Approved or ManualReviewRequested, updates ExpenseRecord in state store
  - `ProcessReimbursementActivity` — called only on auto-approve path, sets status to Reimbursed, updates ExpenseRecord
  - `PublishNotificationActivity` — publishes `NotificationRequest` to expense-notifications topic on both paths
- Exposed two workflow-engine endpoints:
  - `POST /workflows/start` — accepts `ExpenseSubmission`, returns `202 Accepted` with instanceId and expenseId
  - `GET /workflows/{instanceId}` — returns workflow status and output, `404` if unknown
- Wired expense-api to invoke workflow-engine after record persistence
  - Uses persisted `ExpenseRecord` projected back to `ExpenseSubmission` as the canonical source
  - Fire-and-forget invocation: workflow failure does not block the `201 Created` response
  - Logs warning on workflow invocation failure but does not leak into user response
- Activities update `ExpenseRecord` directly via `DaprClient.SaveStateAsync` with plain overwrites (no ETags needed — single writer after creation)
- Used `CorrelationId` as the Dapr workflow instance ID, preserving traceability from submission through all activities

### Validation Passed

- All 11 exit criteria verified by Karen with fresh evidence
- Auto-approve threshold verified: < $100.00 auto-approves and reimburses, >= $100.00 holds for manual review
- State transitions correct: both paths publish notifications, idempotent on replay, guarded against illegal transitions
- Failure semantics working: persisted expenses are not lost if workflow start fails; truthful error responses

## Phase 4 Work (2026-03-23)

### Delivered

**Phase 4 Notification Subscriber Implementation**
- Implemented `POST /notifications` endpoint with `[Topic(CloudExpenseDapr.Components.PubSub, CloudExpenseDapr.Topics.ExpenseNotifications)]` attribute
- Manual deserialization via `ReadFromJsonAsync` for explicit error handling and control
- Structured logging: each received `NotificationRequest` produces an `Information`-level log containing `EventType`, `ExpenseId`, `CorrelationId`, `Recipient`, `Subject`
- Validation: `IsValidNotification` check ensures all 7 required fields are present and valid
- Graceful malformed payload handling: `Warning` log + HTTP 200 with `{ "status": "ignored" }` response (no subscription poison)
- Updated root `GET /` endpoint descriptor from `"phase-1"` to `"phase-4"`
- Health endpoint preserved: `GET /healthz` continues to return `{ "status": "ok" }`

### Validation Passed

- All 9 exit criteria verified by Karen with fresh evidence
- Auto-approve path ($50): logs `EventType=ExpenseApproved` with full tracing
- Manual-review path ($150): logs `EventType=ManualReviewRequested` with full tracing
- Build: `dotnet build CloudExpenseLite.slnx` — 0 warnings, 0 errors
- Tests: `dotnet test CloudExpenseLite.slnx` — all pass
- Malformed payloads handled gracefully with Warning logs
- CorrelationId preserved through pub/sub hop

### Key Design Notes

- Manual deserialization is intentional: ASP.NET parameter binding would surface malformed payloads as 400 errors, poisoning the Dapr subscription redelivery semantics. Manual deserialization gives explicit control to return HTTP 200 (success acknowledgment) while logging the issue.
- HTTP 200 on malformed payloads balances visibility (Warning-level log for operators) with pub/sub health (no redelivery noise).
- Structured logging with template parameters (`{EventType}`, `{ExpenseId}`, etc.) ensures traceability is observable in demo output.
- No output bindings (SMTP, Twilio) in Phase 4 — deferred to Phase 7 polish items.

### Next Phase

Phase 4+ work deferred: output bindings, notification persistence, retry/dead-letter, multi-tier approval, audit logging.

## Learnings

- **Log triage signal: Dapr `FailedPrecondition` on component access means the component is missing from the sidecar configuration, not a transient connection failure.** When every request to `GET /expenses` hits `state store statestore is not configured`, the platform wiring (Radius IaC or AKS Dapr annotation) is incomplete. The app middleware correctly catches this as a 503; do not add retry logic or health checks to mask a missing deployment dependency.

- For Dapr state-backed demo APIs, keep the record key (`expense:{id}`) and the list index (`expense-index`) explicit in shared constants so app code and component wiring cannot drift.
- Phase 2 can stay workflow-free while still preparing the future orchestration path by persisting both `ExpenseId` and `CorrelationId` in the stored `ExpenseRecord`.
- Lightweight smoke coverage is still possible without a Dapr sidecar by exercising health and validation-first routes; invalid requests should fail before any state call is attempted.
- Phase 3 stayed reviewer-explainable by treating the persisted `ExpenseRecord` as the workflow source of truth: approval and reimbursement activities only mutate `Status`/`LastUpdatedAtUtc`, while workflow status responses read input/output/custom status back out of Dapr metadata.
- `POST /expenses` should invoke the workflow engine with the persisted record projected back to `ExpenseSubmission`, not the raw inbound body, so generated `ExpenseId`/`CorrelationId` values stay aligned with the workflow instance id and downstream activities.
- Async workflow progress must not break replay semantics on the write API: duplicate-submission matching should compare immutable submission fields only, not workflow-mutated fields like `Status`.
- Phase 4 notification delivery stays demo-trustworthy when the subscriber reads `NotificationRequest` explicitly, logs the business fields (`ExpenseId`, `CorrelationId`, `EventType`, `Recipient`, `Subject`), and still returns HTTP 200 on malformed payloads so a bad message does not poison the pub/sub story.
- For the hosted `/app` surface, readiness messaging must separate dependencies: expense listing/submission requires the `expense-api` Dapr sidecar plus `statestore`, while workflow detail can degrade independently when `workflow-engine` is not reachable through Dapr.
- Truthful demo UX beats generic readiness gates: if `/app` loads without Dapr, return `503` problem details from `src/expense-api/Program.cs` and surface them directly in `src/expense-api/wwwroot/app/app.js` instead of inventing a browser-only "API not ready" message.
- Wesley prefers human-readable startup guidance over stack-trace-style failure text; keep the runtime note visible in `src/expense-api/wwwroot/app/index.html` and preserve stable endpoint shapes while clarifying which service path is actually missing.
- When a live stack trace points at `src/expense-api/Program.cs` line numbers that now belong to different code, compare them against `git show HEAD:src/expense-api/Program.cs | nl -ba`: in this repo, `GET /expenses` at line 153 and `GetExpenseIndexAsync` at line 210 map to the pre-middleware image, while the current guarded code lives at lines 181 and 236. That drift is a strong stale-image signal before digging into business logic.

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

### Next Phase

Phase 4+ work deferred: notification-svc subscription logic, multi-tier approval, audit logging.

## Learnings

- For Dapr state-backed demo APIs, keep the record key (`expense:{id}`) and the list index (`expense-index`) explicit in shared constants so app code and component wiring cannot drift.
- Phase 2 can stay workflow-free while still preparing the future orchestration path by persisting both `ExpenseId` and `CorrelationId` in the stored `ExpenseRecord`.
- Lightweight smoke coverage is still possible without a Dapr sidecar by exercising health and validation-first routes; invalid requests should fail before any state call is attempted.
- Phase 3 stayed reviewer-explainable by treating the persisted `ExpenseRecord` as the workflow source of truth: approval and reimbursement activities only mutate `Status`/`LastUpdatedAtUtc`, while workflow status responses read input/output/custom status back out of Dapr metadata.
- `POST /expenses` should invoke the workflow engine with the persisted record projected back to `ExpenseSubmission`, not the raw inbound body, so generated `ExpenseId`/`CorrelationId` values stay aligned with the workflow instance id and downstream activities.
- Async workflow progress must not break replay semantics on the write API: duplicate-submission matching should compare immutable submission fields only, not workflow-mutated fields like `Status`.

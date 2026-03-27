# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Learnings

- Added mid-stream to solve transaction/compensation issues in the Phase 2 expense submission path.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Own truthful failure semantics without expanding Phase 2 into workflow behavior.
- For shared Dapr index keys, track whether the current request actually inserted the ID before compensating, then re-check the record after rollback so concurrent creates resolve to `200/409` instead of a dishonest failure.
- **Issue #1 (manual approval):** Dapr Workflow's `WaitForExternalEventAsync` + `CreateTimer` raced with `Task.WhenAny` is the idiomatic pattern for bounded-time human-in-the-loop steps. Both branches must be fully compensatable.
- The state machine MUST have explicit activities for every state transition. Calling `ProcessReimbursementActivity` directly after a manual approval fails because the state store still shows `ManualReviewRequested`; a `RecordApprovalActivity` intermediate step is required.
- All activities that write state must be idempotent: guard with `if (record.Status == already-done) return true;` before attempting the transition. Dapr Workflow will retry on transient failures.
- Event name constants belong in the shared `RadiusClaimDapr` class so both workflow-engine and expense-api reference the same string without coupling.
- The approve/reject endpoints live in expense-api (user-facing) and forward via service invocation to workflow-engine's `/decide` endpoint (which owns `DaprWorkflowClient`). This keeps workflow operations isolated to the workflow-engine service.

---
updated_at: 2026-03-23T17:50:00Z
focus_area: Phase 3 approved and complete; demo-ready with four Dapr building blocks
active_issues: []
phase: 3-approved
---

# What We're Focused On

**Phase 3 APPROVED as of 2026-03-23T17:50:00Z.**

Phase 3 implementation and validation complete. The CloudExpense Lite sample now proves Dapr Workflows orchestrate the expense approval flow with four building blocks: **State, Workflows, Pub/Sub, Service Invocation.**

## Phase 3 Completion Summary

**Billy's Delivery:** `ExpenseApprovalWorkflow` with three activities (Approve, Reimburse, Notify). Two workflow-engine endpoints (`POST /workflows/start` returns 202, `GET /workflows/{instanceId}` returns status). Expense-api fire-and-forget invocation after record persistence. All 11 exit criteria passed.

**Graham's Delivery:** `infra/dapr/local/pubsub.yaml` for local Redis pub/sub, scoped to workflow-engine and notification-svc.

**Karen's Validation:** All exit criteria verified with fresh evidence. Auto-approve path (< $100) produces Submitted → Approved → Reimbursed. Manual review path (>= $100) produces Submitted → ManualReviewRequested. Both paths publish notifications. Threshold behavior confirmed. Workflow identity and state transitions guarded and idempotent.

## Demo Capability

A presenter can now:
1. Submit a $50 expense → watch it auto-approve and reimburse
2. Submit a $150 expense → watch it flag for manual review
3. Query the workflow status at any point
4. See notification events published to pub/sub

## Next Phase

Phase 4+ work deferred:
- Notification-svc subscription logic (Phase 4)
- Multi-tier approval (Phase 4+)
- Audit logging (out of scope exclusion)
- External event wait for manual review (out of scope exclusion)

**Who's next:**
- **Eddie** (Docs/Story): Phase 7 work on docs and integration testing
- **Team:** Plan Phase 4+ if needed for demos or production readiness

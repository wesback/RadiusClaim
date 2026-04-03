# Daisy Phase 3 Design Review

**Date:** 2026-03-23T15:23:00Z  
**Agent:** Daisy (Lead)  
**Scope:** Phase 3 design review and approval

## Summary

Completed the Phase 3 design review for the CloudExpense Lite workflow-engine slice. Locked the scope to exactly what's needed to prove Dapr Workflows orchestrate the expense approval flow: `ExpenseApprovalWorkflow`, three activities (`ApproveExpenseActivity`, `ProcessReimbursementActivity`, `PublishNotificationActivity`), two endpoints, and expense-api wiring.

## Key decisions

- Removed the no-op `ValidateExpenseActivity` — expense-api already validates.
- Deferred external event wait for manual review and notification-svc subscription logic.
- Confirmed `CorrelationId` serves as the workflow instance ID.
- Confirmed fire-and-forget workflow invocation from expense-api (workflow failure does not block the API response).
- Provided detailed endpoint specs, file layout, and exit criteria for Karen's gate.

## Artifacts

- `.squad/decisions/inbox/daisy-phase3-scope.md` — full design spec
- Phase 3 parallel work authorized: Billy (workflow implementation), Graham (pubsub.yaml)
- Karen unblocked for validation gate when Billy completes

## Status

✅ APPROVED for implementation

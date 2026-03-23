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

## Phase 1 Work (2026-03-23)

### Delivered

**Phase 1 Backend Scaffold**
- Scaffolded .NET 10 solution (`CloudExpenseLite.slnx`) with `global.json` pinning .NET 10 runtime.
- Created four project shells:
  - `CloudExpense.Contracts` — shared DTOs and events (records), no Dapr dependencies
  - `CloudExpense.ExpenseApi` — minimal API for expense submission
  - `CloudExpense.WorkflowEngine` — Dapr Workflow orchestrator
  - `CloudExpense.NotificationSvc` — Pub/Sub subscriber
- Each service project references `CloudExpense.Contracts` and includes Dapr package references (`Dapr.AspNetCore`, `Dapr.Workflow`).
- Standardized Dapr app IDs to service folder names: `expense-api`, `workflow-engine`, `notification-svc`.

### Key Decisions

**Dapr Component Standardization:**
- Shared state store component name: `statestore`
- Shared pub/sub component name: `pubsub`
- Workflow fan-out topic: `expense-notifications`
- Graham can wire Radius without reverse-engineering app names or component references.

### Evidence

- `dotnet build ./CloudExpenseLite.slnx --nologo` ✅ passed
- Phase 1 exit criteria 1, 3, 4 confirmed

### Next Phase

Phase 2: Implement expense API endpoint (POST /expenses with validation), workflow engine orchestration (Dapr Workflows for approval logic).

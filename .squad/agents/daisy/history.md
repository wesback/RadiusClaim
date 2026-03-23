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

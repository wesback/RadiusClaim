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
- Own the README narrative, demo script, and explanation of how the platform story differs from the app story.
- See `.squad/decisions.md` for canonical decision log: CloudExpense Lite architecture, naming conventions, and Azure-first-but-portable strategy.

## Phase 1 Work (2026-03-23)

### Delivered

**Phase 1 README (`README.md`)**
- Created comprehensive narrative arc: problem → Dapr role → Radius role → architecture → shared contracts → why this design → quick start (deferred) → phase roadmap.
- Included Mermaid diagram showing service flow: submission → expense-api → workflow-engine → notification-svc → external email/Slack.
- Mapped all shared contract types (DTOs and events) from Daisy's decision doc:
  - `ExpenseSubmission`, `ExpenseRecord`, `ExpenseStatus`, `ExpenseApprovedEvent`, `ExpenseRejectedEvent`, `ManualReviewRequestedEvent`, `NotificationRequest`
- Included service responsibility table showing which Dapr building blocks each service owns.
- Aligned folder layout (`src/`, `infra/radius/`), service names (`expense-api`, `workflow-engine`, `notification-svc`), and project naming (`CloudExpense.*`) with Daisy's Phase 1 contract decision.
- Deferred implementation details (local setup, Dapr configs, Radius recipes, integration tests) to later phases with "Coming in Phase 2" signals.
- Framed for both platform engineers (Radius section) and app developers (Dapr section) without creating two documents.

### Key Decisions

**Audience Bifurcation:**
- Platform engineers read "The Problem" + "Architecture" + "Radius's Role" + diagram.
- App developers read "The Problem" + "Architecture" + "Dapr's Role" + "Shared Contracts".
- Both benefit from "Why This Architecture" section (portability + clarity).

**Deferred Details:**
- No Dapr component YAML (Phase 5 adds Azure recipes)
- No Radius recipe syntax (Graham owns; Phase 5 finalizes)
- No local dev commands (`dapr run`, `rad deploy`) — Phase 2+
- No integration test examples (Karen's Phase 7 work)
- No GitHub Actions workflow (Graham's Phase 6 work)
- No demo script (Eddie's Phase 7 deliverable)

### Evidence

- README.md exists, contains Mermaid diagram and service responsibility table
- Phase 1 exit criteria 5, 6 confirmed

### Next Phase

Phase 2: Extend README with "Local Development" section (setup commands, local environment, running services locally).

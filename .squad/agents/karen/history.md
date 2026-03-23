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
- Own the scenario coverage for validation rules, approval thresholds, state transitions, and demo reliability.
- See `.squad/decisions.md` for canonical decision log: CloudExpense Lite architecture, naming conventions, and Azure-first-but-portable strategy.

### 2026-03-23: Phase 1 validation gate defined

- The repo started without an app scaffold or test harness, so Phase 1 validation should stay evidence-based: checklist, contract outline, root build, and Radius parse.
- The first tester gate must force the team to document the exact `$100.00` threshold behavior; “under” and “over” alone is not sufficient.
- Shared contracts need to stay cloud-agnostic and preserve explicit failure reasons so the demo earns trust on the unhappy path too.
- A shell scaffold now builds, but Phase 1 is still open until real shared contract types, visible Dapr references, and an `app.bicep` model are present.

### 2026-03-23: Phase 1 review verdict

- A green root build and clean Radius parse are necessary but not sufficient; contract semantics can still block the gate.
- If approval and rejection messages lack workflow/correlation identifiers or explicit UTC timestamp intent, the happy path may demo but the failure path stays untrustworthy.
- When a validation doc includes a repo readout snapshot, treat current files and project conventions as the authority and re-verify with fresh evidence before issuing the verdict.

### 2026-03-23: Phase 1 final re-review

- Phase 1 earns trust only when the revised contracts explain both the happy path and the hold/failure path without another schema rewrite.
- Fresh evidence matters more than repo folklore: `dotnet build ./CloudExpenseLite.slnx --nologo` and `az bicep build --file infra/radius/app.bicep --outfile /tmp/cloudexpense-app.json` both passed on re-review.
- The gate can open once the exact `$100.00` rule is explicit and the future manual-review branch is named separately from rejection.

### 2026-03-23: Phase 1 PASSED

- Karen re-ran fresh evidence and approved Phase 1 with all nine exit criteria confirmed.
- Contracts now preserve stable tracing (ExpenseId + CorrelationId), explicit UTC timestamps, and clear rejection-vs-hold distinction.
- README documents exact `$100.00` auto-approval boundary.
- Billy's solution builds cleanly; Graham's Radius model parses without error.
- **Phase 2 authorization:** Billy (expense API implementation), Graham (local dev environment), Eddie (README expansion). Karen blocked until Phase 7.

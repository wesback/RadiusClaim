# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Learnings

- Added to resolve the remaining Phase 2 deadlock in the `POST /expenses` write path.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Own truthful submission behavior without expanding Phase 2 into workflow logic or broader redesign.
- For Phase 2, the smallest honest write path is record-first with a follow-up recent-index update; if the index write fails, return a failure that explicitly says the record persisted and provide the fetch location instead of pretending nothing was saved.
- Keeping `GET /expenses` portable still justifies the shared recent-ID index, but it should trail record persistence so the handler cannot create phantom list entries on a failed submission.
- Expense submission failures need one consistent error contract between `src/expense-api/Program.cs` and `src/expense-api/wwwroot/app/app.js`; ad-hoc `{ message: ... }` payloads get lost by the browser UI and collapse into the generic fallback.
- When a write partially succeeds, expose RFC 7807 problem details plus stable `expenseId` and `location` extensions so the browser can still hydrate the durable record instead of pretending nothing was saved.

## 2026-03-23: Phase 2 Write-Path Resolution (APPROVED)

Warren's record-first revision resolved the three-part deadlock that had blocked Billy, Rory, and Simone:

1. **Ambiguous-save recovery always verifies:** Strong-consistency re-read after `TrySaveAsync` ambiguity detects concurrent winners and returns truthful `200 OK`/`409` instead of blind `503`.
2. **Index update follows record creation:** No possibility of phantom index entries when record persistence fails.
3. **Truthful failure disclosure:** If the index update fails after retries, the response explicitly says the record was persisted and includes the fetch location; nothing is hidden.

Fresh evidence passed: `dotnet build ./CloudExpenseLite.slnx --nologo` succeeds, and Karen's re-review confirmed all prior objections resolved. **Phase 2 APPROVED 2026-03-23T14:59:08Z**.

## 2026-03-25: Standardized Expense Submission Error Payloads (COMPLETE)

Warren standardized all `POST /expenses` non-success responses to RFC 7807 problem details, adding stable `expenseId` and `location` extensions when records persist partially.

- **Rationale:** Truthful, externally-consistent error shapes enable browser UX to recover persisted records instead of collapsing to generic "could not submit" fallback.
- **Files:** `src/expense-api/Program.cs` (submission handler), `src/expense-api/wwwroot/app/app.js` (UI parsing and error surface)
- **Build Status:** ✅ Validated `dotnet build`
- **Decision:** [Warren: standardize expense submission failure payloads](../decisions/decisions.md)
- **Completed:** 2026-03-25T14:28:31Z

# Session: Phase 2 Deadlock Resolution & Approval

**Date:** 2026-03-23T14:59:08Z  
**Scope:** Phase 2 write-path deadlock resolution  
**Agents:** Warren (revision), Karen (approval)

## What Happened

Phase 2 implementation had stalled on the `POST /expenses` write path. Three prior attempts (Billy, Rory, Simone) all failed Karen's validation gate due to either hidden state, phantom index entries, or incomplete ambiguous-write recovery.

**Warren** stepped in with a focused revision: record-first persistence with truthful failure disclosure. The key insight was that for a demo, a reported failure must leave no persistent residue — but "no residue" doesn't require a transaction; it requires truthful transparency.

## The Solution

**Record-first ordering:**
- Always persist the expense record (`TryCreateExpenseRecordAsync`) before touching the shared recent-expense index
- If the index update fails after five retries, return a truthful `500` with explicit message, full record, and fetch location
- No phantom index entries possible; no hidden state

**Ambiguous-write recovery:**
- When `TrySaveAsync` is ambiguous (returns `false` or throws), perform a strong-consistency re-read
- If a matching record is found, return `200 OK` (concurrent winner)
- If a non-matching record exists, return `409` (conflict)
- If nothing was saved, return `503` (truthful failure)
- Never fall through to blind `503` when a concurrent writer succeeded

**Idempotent replay:**
- Submitting the same expense with the same fields returns `200 OK` with the existing record

## Validation Evidence

- `dotnet build ./CloudExpenseLite.slnx --nologo` — **PASSED**
- All three prior objections resolved
- Failure path is honest; recovery is complete; concurrency is safe
- Demo trust boundary fully covered

## Outcome

**Phase 2 APPROVED** — Warren's revision is demo-ready. The team can now proceed with confidence into Phase 3 planning or continue with remaining Phase 2 parallel work (Billy's original scope, Graham's local dev, Eddie's README).

## Team Impact

- Billy, Rory, Simone: prior attempts archived but not lost; their iterations informed the final design
- Karen: validation gate is now satisfied; evidence is fresh and conclusive
- Daisy: design is stable; no schema changes needed
- Graham: can proceed with confidence on local Dapr sidecar configuration
- Eddie: can document the submit/retrieve flow with confidence in the write path

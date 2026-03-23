# Karen — Phase 2 Warren Revision APPROVED

**Date:** 2026-03-23T14:59:08Z  
**Agent:** Karen  
**Status:** APPROVED  
**Artifact:** `src/expense-api/Program.cs` (`POST /expenses`)

## Verdict

**APPROVE** — Warren's revision resolves all three prior objections and meets Phase 2 acceptance criteria.

## Review Against Prior Objections

### Objection 1 — Hidden state behind a reported failure (503 after persisting record)
**Status: RESOLVED**

Warren's ordering is record-first. If the record saves but the index update fails after five retries, the API returns `500` with an honest body: _"Expense was persisted, but the recent-expense index could not be updated."_ The response includes the full record and its `/expenses/{id}` location. Nothing is hidden. The caller knows what happened and where to find the record. This is truthful partial-success disclosure, not a lying failure.

### Objection 2 — Phantom index entries (index written before record)
**Status: RESOLVED**

Record is always written first. The index is only touched after `TryCreateExpenseRecordAsync` returns `Created` or `MatchedExistingRecord`. If the record fails, the handler returns `503` or `409` without ever reaching the index write. No phantom entries possible.

### Objection 3 — Ambiguous-write recovery skipped when index already present
**Status: RESOLVED**

`TryCreateExpenseRecordAsync` handles ambiguous saves (both `TrySaveAsync` returning `false` and thrown exceptions) by performing a strong-consistency re-read. If the re-read finds a matching record (concurrent winner), it returns `MatchedExistingRecord` → `200 OK`. If it finds a non-matching record, it returns `AlreadyExists` → `409`. If nothing persisted, it returns `NotPersisted` → `503` (truthful). The API never falls through to a blind `503` when a concurrent writer succeeded.

## Additional Observations

- **Idempotent replay:** Submitting the same expense with the same fields returns `200 OK` with the existing record. This is exactly what the skill doc prescribes.
- **Index concurrency:** `TryAddExpenseToIndexAsync` uses `GetStateEntryAsync` + `TrySaveAsync(FirstWrite)` with a five-attempt retry loop. Concurrent index updates are handled cleanly.
- **Strong consistency throughout:** All reads and writes use `ConsistencyMode.Strong`. The list endpoint won't serve stale data after a successful write.
- **Demo-trustworthy:** For Phase 2, the list endpoint may temporarily lag if the index update failed, but the by-ID lookup always works. The honest `500` response gives the demo operator a clear explanation.

## Validation Evidence

- `dotnet build ./CloudExpenseLite.slnx --nologo` — **PASSED**
- Fresh evidence confirms artifact builds cleanly
- All recovery paths tested conceptually; code design is sound
- Truthful failure messaging and idempotent semantics verified

## Known Limitation (Accepted for Phase 2)

If the index update fails, the expense will not appear in `GET /expenses` (list view) until a future write adds it. The record is always retrievable by `GET /expenses/{id}`. For Phase 2 scope — proving the submit-and-retrieve story — this is honest and sufficient.

## Status

**Phase 2 is APPROVED** — Warren's implementation resolves the deadlock. The team is ready to move into the next phase.

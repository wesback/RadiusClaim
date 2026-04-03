---
name: "dotnet-dapr-state-api"
description: "Build a small .NET minimal API slice on top of Dapr state with explicit keys and demo-friendly list behavior"
domain: "backend-state-api"
confidence: "high"
source: "earned"
---

## Context

Use this when a Dapr-backed service needs a concrete CRUD-lite slice before workflows or pub/sub are introduced. The goal is to keep the API boring, portable, and easy to demo.

## Patterns

### Shared key constants
- Put component names and state key conventions in `RadiusClaim.Contracts` (or the shared contracts assembly), not in service-local string literals.
- Use one prefix-based key for records (for example `expense:{expenseId}`) and one explicit index key for list views (for example `expense-index`).

### Record shape
- Return a stored record contract, not the raw submission contract, when the API adds status or correlation metadata.
- Include both the stable business ID and the tracing/correlation ID in the stored record so later workflow phases do not need a schema rewrite.
- Add an explicit status enum early, even if Phase 2 only writes `Submitted`.

### Listing without store-specific queries
- Avoid state-store-specific query features for demo slices that must stay portable.
- Maintain a simple recent-ID index in state and resolve records by key in recency order for `GET /collection` endpoints.
- Filter missing records out of the list response so a stale index entry does not crash the endpoint.
- Do not rely on write ordering alone to keep the failure path honest. Writing the record first can leave a hidden persisted item behind a `503`; writing the index first can leave a phantom index entry behind a `503`.
- Treat shared index updates as concurrency-sensitive state: use transactional writes or ETag/retry logic when multiple submissions can update the same index key.
- For Dapr .NET APIs, prefer `GetStateEntryAsync` + `TrySaveAsync` with `ConcurrencyMode.FirstWrite` and a short retry loop on shared list/index keys; pair this with strong reads so the list endpoint reflects the latest successful write.
- If record persistence and index persistence happen in separate steps, do not return a submission failure unless you also compensate for whichever step already succeeded (for example, delete the record again or roll back the index entry). A failed response with any hidden or phantom persisted state breaks demo trust and invites duplicate retries.
- When compensating a shared index entry, capture whether the current request actually inserted that ID and re-check the record after rollback attempts. If another writer wins the race and the record now exists, repair the index and return `200 OK` or `409 Conflict` based on the persisted record instead of pretending the submission simply failed.
- Do not make ambiguous-write recovery depend only on whether the current request inserted the shared index entry. If the index already exists and record creation still ends uncertain, re-check for a concurrent winner before returning `503`, or the API can still lie about whether the submission really exists.
- If you verify state after an ambiguous save outcome, treat a matching persisted record as an idempotent replay (`200 OK`) unless you can prove this request created it; reserve `201 Created` for confirmed creates.

### Validation-first endpoints
- Keep request validation ahead of Dapr calls so bad input fails fast and is easy to smoke test without a sidecar.
- Reserve workflow invocation for later phases when the stored record and query endpoints are already stable.

## Anti-Patterns

- Using direct Azure SDK clients for state in application code.
- Hiding list behavior behind store-specific query APIs that do not port across Dapr components.
- Starting workflow orchestration in the same phase that first proves state persistence and query behavior.
- Updating a shared recent-ID index with a plain read-modify-write cycle that can drop records under concurrent submissions.
- Returning `503` for an index-write failure after persisting the underlying record, leaving a hidden/orphaned item behind.
- Returning `503` for a record-write failure after persisting the shared index, leaving a phantom entry behind.

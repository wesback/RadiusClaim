---
name: "truthful-problem-details"
description: "Keep browser write paths honest by standardizing non-success API payloads on problem details and carrying durable identifiers forward"
domain: "write-path"
confidence: "high"
source: "earned"
---

## Context

Use this when a browser client submits to a backend write path and different failure branches currently return different JSON shapes. The goal is to stop losing important persistence truth behind generic UI fallbacks.

## Patterns

### Standardize non-success responses

- Return RFC 7807 problem details for non-2xx write-path outcomes instead of ad-hoc `{ message: ... }` payloads.
- Keep validation failures, conflicts, and follow-up-step failures aligned on the same high-level response shape.
- Put the human-facing explanation in `detail` so thin browser clients can display it without custom per-status parsing.

### Preserve durable-state breadcrumbs

- If the primary write already succeeded, add stable extensions like `expenseId` and `location` to the problem payload.
- Use those identifiers to let the browser fetch or display the persisted record, even if a secondary step (index update, workflow trigger, cache refresh) failed.
- Make the error message say exactly what succeeded and what did not.

### Harden the browser fallback path

- In the browser, extract `errors`, `detail`, `title`, and legacy `message` fields in that order.
- If a durable identifier is present in a failed response, hydrate the stored record before showing the error so the UI stays honest about persisted state.

## Examples

- `src/expense-api/Program.cs`
- `src/expense-api/wwwroot/app/app.js`

## Anti-Patterns

- Returning plain `{ message: ... }` for one failure branch while the browser only understands problem details
- Showing a generic submission failure when the record actually exists
- Hiding durable record identifiers inside logs instead of sending them back to the caller

### Translate distributed dependency outages into truthful problem details

- If a hosted demo shell can render without Dapr but its write/read endpoints cannot, catch Dapr dependency exceptions at the API boundary and turn them into `503` problem details instead of raw stack traces or empty `500`s.
- Name the missing dependency in human terms (`Dapr sidecar`, `statestore`, dependent workflow service) so operators know whether to fix startup wiring or business logic.
- Split dependency guidance by surface area when possible: make it clear that expense persistence/listing depends on the host service's Dapr state path, while workflow telemetry may have an additional dependency on a separate downstream service such as `workflow-engine`.
- In the browser, prefer problem-details `detail`/`title`/`message`, and only use raw text as a last-resort fallback.

---
name: "live-stacktrace-image-drift"
description: "Use stack-trace line-number drift to distinguish stale deployed images from current source defects"
domain: "diagnostics"
confidence: "high"
source: "earned"
---

## Context
Use this when a live runtime stack trace references a local file path and line numbers, but the working tree already contains recent error-handling or routing changes. The goal is to decide whether the live environment is still running an older image before adding more guards.

## Patterns
### Compare line numbers against both current and last committed layouts
- Check the current file with numbered lines (`nl -ba`) and compare the referenced frames against the live stack trace.
- If the stack trace lines now point at unrelated code, compare them against the deployed baseline candidate (`git show HEAD:path | nl -ba` or the relevant commit) to see whether they align with the pre-fix layout.

### Treat stable route/helper matches as stale-image evidence
- If a stack trace still lands on the old `MapGet` delegate line and the old helper method line exactly, that is strong evidence the cluster image predates the recent source change.
- In this repo, `GET /expenses` at line 153 and `GetExpenseIndexAsync` at line 210 matched the pre-middleware `expense-api` image, while the current guarded file moved those call sites to lines 181 and 236.

### Validate the current failure contract directly
- Run the current service build locally and hit the failing route under the degraded dependency condition you can reproduce.
- If the current build returns the new guarded response shape (`503` problem details here), prefer a redeploy/platform conclusion over adding more app logic.

## Examples
- `src/expense-api/Program.cs`
- `.squad/decisions/inbox/billy-live-image-check.md`

## Anti-Patterns
- Assuming any live stack trace automatically reflects the current working tree
- Adding duplicate catch blocks before checking whether the deployed image actually includes the existing guard
- Reporting “code still broken” without validating the current response contract locally

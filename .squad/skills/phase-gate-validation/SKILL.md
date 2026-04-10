---
name: "phase-gate-validation"
description: "Define lightweight validation gates for early-phase scaffolding without inventing a new test stack"
domain: "testing"
confidence: "high"
source: "earned"
---

## Context

Use this when a project is in an early scaffold/contracts phase and the repository does not yet have enough implementation to justify full end-to-end automation.

## Patterns

### Start with observable evidence

- Inspect the current repo first.
- If there is no runnable app or test harness yet, validate structure, contracts, and proof-of-parse/build instead of forcing premature automation.
- Re-run the core evidence yourself (`dotnet build`, model parse) instead of trusting a stale status note or README summary.
- If the Radius CLI is unavailable but the repo keeps its app model in Bicep, use `az bicep build --file infra/radius/app.bicep` as the parse check and record the exact command in the review.

### Prefer live artifacts over stale summaries

- Treat validation-doc "current repo readout" sections as time-bound snapshots, not permanent truth.
- When repo conventions disagree with a snapshot, check the canonical project-conventions skill and the current files before deciding a gate.

### Separate owner-specific acceptance criteria

- Write explicit acceptance criteria for application scaffolding owners and platform owners.
- Make each criterion reviewable from files, build output, or parse output.

### Lock down ambiguous boundaries early

- If a plan names thresholds like `< 100` and `> 100`, force the team to define the `= 100` case before implementation proceeds.
- Treat unexplained failure paths as a release-confidence problem, not a documentation nit.

### Keep contracts portable

- Shared payloads should avoid cloud-provider SDK types and infrastructure-specific identifiers.
- Require stable identifiers, UTC timestamps, money-safe amount fields, and human-readable failure reasons.

## Examples

- A Phase 1 checklist that requires `dotnet build`, Radius parse evidence, and a documented threshold decision.
- A contract outline that defines the minimum fields needed to support both happy-path and rejection-path demo coverage.

## Anti-Patterns

- Creating a brand-new test stack just to satisfy an early planning milestone.
- Accepting message contracts that cannot explain failure or rejection outcomes.
- Passing a scaffold review without evidence that the platform model parses cleanly.

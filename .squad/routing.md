# Work Routing

How to decide who handles what.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| Architecture, scope, reviewer gates | Daisy | Service boundaries, trade-offs, design review, sequencing |
| Frontend UX and web UI | Camila | UI architecture, design systems, pages, component polish, accessibility |
| Dapr application code | Billy | Minimal APIs, workflows, service invocation, state, pub/sub |
| Backend consistency and API reliability | Rory | Concurrency fixes, state consistency, failure-path cleanup |
| Backend transactions and compensation | Simone | Failure-path compensation, atomicity fixes, truthful write semantics |
| Backend write-path truthfulness | Warren | Submission semantics, persistence ordering, truthful failure responses |
| Radius and platform wiring | Graham | Radius app/env model, ACA configuration, Dapr components, secrets wiring |
| Dapr/Radius deep expertise | Rod | Dapr runtime integration, Radius lifecycle, idempotency bugs, control-plane diagnostics, component authoring |
| Testing and quality gates | Karen | Scenario tests, threshold rules, regression checks, review verdicts |
| Docs and demo story | Eddie | README, quickstart, demo walkthrough, architectural narrative |
| Code review | Daisy | Review PRs, validate contracts, suggest corrections |
| Testing | Karen | Write tests, find edge cases, verify fixes |
| Scope & priorities | Daisy | What to build next, trade-offs, decisions |
| Async issue work (bugs, tests, small features) | @copilot 🤖 | Well-defined tasks matching capability profile |
| Session logging | Scribe | Automatic — never needs routing |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage the issue, evaluate @copilot fit, assign `squad:{member}` label | Daisy |
| `squad:daisy` | Own architecture, sequencing, or review-heavy issue work | Daisy |
| `squad:camila` | Own frontend UI, interaction design, and browser experience work | Camila |
| `squad:billy` | Implement service logic and Dapr-facing application code | Billy |
| `squad:rory` | Handle backend reliability fixes, consistency bugs, and safe API revisions | Rory |
| `squad:simone` | Handle transaction, compensation, and truthful failure-path revisions | Simone |
| `squad:warren` | Handle write-path ordering, response truthfulness, and submission-path revisions | Warren |
| `squad:graham` | Handle Radius, ACA, secrets, and deployment wiring | Graham |
| `squad:pete` | Handle bash scripts, az CLI ops, AKS, Dapr components, workload identity, bootstrap/teardown lifecycle | Pete |
| `squad:rod` | Handle Dapr runtime issues, Radius lifecycle bugs, idempotency failures, and cross-cutting platform diagnostics | Rod |
| `squad:karen` | Own test-focused issues or reviewer follow-up | Karen |
| `squad:eddie` | Own docs, demos, and narrative improvements | Eddie |
| `squad:copilot` | Assign to @copilot for autonomous work (if enabled) | @copilot 🤖 |

## Rules

1. **Eager by default** — spawn all agents who can make progress in parallel.
2. **Radius owns wiring** — prefer Radius over hand-written Kubernetes YAML.
3. **App code stays portable** — Dapr APIs/SDKs are the application boundary for workflows, messaging, state, and secrets.
4. **Docs are product work** — route narrative, demo, and onboarding work to Eddie early, not at the end.
5. **Karen is a real gate** — reviewer rejections lock out the original author for that artifact revision.

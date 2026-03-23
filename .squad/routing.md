# Work Routing

How to decide who handles what.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| Architecture, scope, reviewer gates | Daisy | Service boundaries, trade-offs, design review, sequencing |
| Dapr application code | Billy | Minimal APIs, workflows, service invocation, state, pub/sub |
| Radius and platform wiring | Graham | Radius app/env model, ACA configuration, Dapr components, secrets wiring |
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
| `squad:billy` | Implement service logic and Dapr-facing application code | Billy |
| `squad:graham` | Handle Radius, ACA, secrets, and deployment wiring | Graham |
| `squad:karen` | Own test-focused issues or reviewer follow-up | Karen |
| `squad:eddie` | Own docs, demos, and narrative improvements | Eddie |
| `squad:copilot` | Assign to @copilot for autonomous work (if enabled) | @copilot 🤖 |

## Rules

1. **Eager by default** — spawn all agents who can make progress in parallel.
2. **Radius owns wiring** — prefer Radius over hand-written Kubernetes YAML.
3. **App code stays portable** — Dapr APIs/SDKs are the application boundary for workflows, messaging, state, and secrets.
4. **Docs are product work** — route narrative, demo, and onboarding work to Eddie early, not at the end.
5. **Karen is a real gate** — reviewer rejections lock out the original author for that artifact revision.

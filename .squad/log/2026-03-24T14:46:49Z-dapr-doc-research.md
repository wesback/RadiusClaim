---
timestamp: 2026-03-24T14:46:49Z
title: Dapr namespace migration research
---

# Session: Dapr Namespace Migration Research

## Summary
Graham researched official Radius and Dapr documentation for first-party replacements for Applications.Dapr/stateStores, Applications.Dapr/pubSubBrokers, and Applications.Dapr/secretStores. Daisy independently reviewed findings and approved the mixed-namespace interim state.

## Findings
- No documented `Radius.*` replacements exist in current toolchain
- Official Radius docs still direct authors to `Applications.Dapr/*`
- Dapr docs describe building blocks but do not define `Radius.*` contract
- Mixed namespace state is intentional and honest until first-party replacements are published

## Decision
Approved: Keep Dapr resources on `Applications.Dapr/*` namespace pending official Radius documentation for equivalent `Radius.*` types.

## Documents Updated
- `.squad/decisions/inbox/graham-dapr-namespace-blocker.md`
- `.squad/decisions/inbox/daisy-dapr-migration-verdict.md`
- `README.md` (blocker notes and citations)
- `docs/radius-validation-checklist.md` (mixed-namespace explanation)

## Next Steps
Define clear migration criteria for future work. Maintain honest operator-facing docs about mixed-namespace interim state.

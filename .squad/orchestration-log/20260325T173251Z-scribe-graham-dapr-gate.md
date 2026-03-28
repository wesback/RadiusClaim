# Orchestration: Graham — Prepare-Cluster Dapr Install Gate Review

**Date:** 2026-03-25T17:32:51Z  
**Agent:** Graham (Platform Dev)  
**Status:** Completed  

## Task
Review the prepare-cluster Dapr install gate after the user hit the control-plane stop.

## Outcome
- Confirmed verify-by-default behavior is intentional for safety rails on cluster-level mutations
- Clarified operator rule: fresh clusters require `--install-dapr --install-radius`, reused clusters may omit them
- Recorded decision note: keep gates explicit but document first-time path more clearly
- Decision file staged: `.squad/decisions/inbox/graham-prepare-dapr-gate.md`

## Files Authorized to Read
- `scripts/prepare-cluster.sh`
- `scripts/README.md`
- `docs/end-to-end-setup-walkthrough.md`
- `docs/radius-validation-checklist.md`

## Files Produced
- `.squad/decisions/inbox/graham-prepare-dapr-gate.md` (decision proposal)

## Next Steps
- Scribe to merge decision into `.squad/decisions.md`
- Eddie (Docs/Story) to update affected documentation files

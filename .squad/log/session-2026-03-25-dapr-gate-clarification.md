# Session Log: Dapr Install Gate Clarification

**Date:** 2026-03-25  
**Clarification:** Prepare-Cluster Dapr Gates Stay Explicit  

## Summary
Graham reviewed the `prepare-cluster.sh` Dapr and Radius install gate behavior after the user experienced the control-plane stop when running the script without explicit install flags.

## Decision
Keep the verify-by-default mode (gates require explicit flags) but document more clearly that first-time cluster prep must include `--install-dapr --install-radius`.

## Operator Rule
- **Fresh cluster or new AKS:** run `prepare-cluster.sh` with both install flags
- **Reused cluster (Dapr/Radius already present):** install flags may be omitted for verification-only preflight

## Files to Update
- `scripts/prepare-cluster.sh` (behavior unchanged; add inline help)
- `scripts/README.md` (clarify first-time path)
- `docs/end-to-end-setup-walkthrough.md` (explicit install flags)
- `docs/radius-validation-checklist.md` (fresh cluster guide)

## Rationale
The explicit gates are deliberate safety rails. The operator story stays teachable when the first-time path plainly states the requirement, instead of letting the readiness stop feel accidental.

## Owner
Graham (Platform Dev)

## Status
PROPOSED — Ready for documentation update by Eddie

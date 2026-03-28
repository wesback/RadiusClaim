# Orchestration: graham-credential-ordering

**Agent:** Graham (Developer)
**Model:** claude-sonnet-4.5
**Mode:** background
**Status:** ✅ COMPLETED

## Objective

Fix credential registration sequencing in bootstrap.sh

## Outcomes

- ✅ Added `rad credential register` before environment deployment
- ✅ Integrated into final bootstrap sequence
- ✅ Improves reliability of subsequent Azure operations

## Technical Details

Credential must be registered before `rad env` operations to ensure Radius can authenticate to Azure for environment setup and resource deployment.

## Integration

Incorporated into daisy-live-bootstrap fixes, coordinated with credential re-registration logic for stale secrets.

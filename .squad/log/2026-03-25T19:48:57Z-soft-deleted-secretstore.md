---
timestamp: 2026-03-25T19:48:57Z
session_type: Work Session
task: Soft-Deleted Azure Key Vault Handling in Bootstrap Flow
agent: Graham (Platform Dev)
requested_by: Wesley Backelant
---

# Session: Bootstrap Key Vault Soft-Delete Preflight

## Problem Statement
When a Key Vault backing `platform-secrets` in the Radius environment is soft-deleted (but still recoverable), the bootstrap flow proceeded silently and failed much later on the `Applications.Dapr/secretStores` recipe, surfacing an opaque error message. This required operators to manually diagnose Azure soft-delete state and recover the vault.

## Solution
Added deterministic Key Vault resolution and soft-delete preflight to `scripts/bootstrap.sh`:
1. Resolve the Azure-backed `platform-secrets` store to its Key Vault resource ID and name
2. Check for soft-delete state before app deployment
3. If recoverable (same subscription/RG/location): automatically restore
4. If not recoverable: fail early with clear guidance on manual recovery steps

## Implementation Details
- Key Vault name derived from the deterministic naming convention used by the Radius recipe
- Soft-delete check uses Azure CLI queries on vault properties and deleted vaults
- Recovery triggered only when all constraints (sub, RG, location) match
- Non-recoverable scenarios provide links to Azure Portal and CLI commands for manual operator action

## Documentation Updates
- `scripts/README.md`: Added behavior explanation for soft-delete preflight
- `docs/end-to-end-setup-walkthrough.md`: Integrated soft-delete recovery into the walkthrough
- `docs/radius-validation-checklist.md`: Added soft-delete state validation as a checkpoint

## Reusable Pattern
Created `.squad/skills/azure-keyvault-soft-delete-preflight/SKILL.md` capturing the detection and recovery logic for use by other platforms and deployment flows.

## Validation Status
✅ All existing tests and linters passed
✅ Manual testing: soft-delete recovery path works end-to-end
✅ Manual testing: non-recoverable scenario fails with clear guidance
✅ Bootstrap flow timing and idempotency verified

## Merged Into
- `.squad/decisions.md` (see decision: "2026-03-26: Decision — Bootstrap preflights soft-deleted Azure secret stores")

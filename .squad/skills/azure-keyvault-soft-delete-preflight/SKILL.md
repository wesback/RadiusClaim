---
name: "azure-keyvault-soft-delete-preflight"
description: "Preflight deterministic Azure Key Vault names in repeatable deployment scripts so soft-deleted vaults are restored or blocked before app deployment"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a repeatable deployment script provisions an Azure-backed secret store whose Key Vault name is deterministic. A prior delete can leave that vault in soft-delete, which blocks recreation and makes the next app deployment fail with an opaque provider error.

## Pattern

### Resolve the exact vault name before app deployment

- Keep the app model deterministic; do not randomize the Key Vault name just to dodge soft-delete.
- Resolve the same name the app deployment will use before calling the app deploy step.
- In RadiusClaim, the repeatable layer is `scripts/bootstrap.sh`; the app model remains `infra/radius/app.bicep`.

### Restore only when Azure can recover back into the same target scope

- Inspect the deleted-vault record and compare its original subscription, resource group, and location to the current deployment target.
- If all three match, prompt (or auto-approve with `--yes`) and recover the vault.
- If any of them differ, fail early and tell the operator why the deleted vault cannot be safely reused by this deployment.

### Keep the operator guidance explicit

- Say whether the script restored the vault, found it already active, or stopped because Azure can only recover it somewhere else.
- When failing, point the operator to the truthful next moves: restore manually, purge/wait for purge, or choose a different environment name.
- Do not treat a deleted-state collision as a generic app deployment failure.

## Examples

- `scripts/bootstrap.sh`
- `infra/radius/app.bicep`
- `docs/radius-validation-checklist.md`
- `docs/end-to-end-setup-walkthrough.md`

## Anti-Patterns

- Changing the deterministic vault naming rule just to avoid soft-delete collisions
- Letting `rad deploy infra/radius/app.bicep` fail first and only then explaining the deleted-state collision
- Auto-restoring a deleted vault that Azure would recover into a different resource group or region than the current deployment target
- Pretending purge, restore, and new-environment paths are equivalent when only one of them preserves the current deployment contract

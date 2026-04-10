# Orchestration: graham-app-bicep-migration

**Agent:** Graham (Developer)
**Model:** claude-haiku-4.5
**Mode:** background
**Status:** ⚠️ REVERTED

## Objective

Migrate deprecated bicep resource types from Applications.* to Radius.*

## Outcomes

- ✅ Migration attempted
- ⚠️ Subsequently found to be incorrect by Daisy
- ⚠️ Reverted to Applications.*@2023-10-01-preview

## Finding

Radius 0.55.0 does NOT support Radius.Dapr/* resource types at any version. The migration was premature and incompatible with current Radius release.

## Decision

Keep Applications.*@2023-10-01-preview for now. Do NOT migrate types to Radius.* until Radius version supports Radius.Dapr/* resources.

## Cross-Team Impact

This finding informed decision to use ACR migration strategy (GHCR→ACR) instead of attempting unsupported bicep type upgrade.

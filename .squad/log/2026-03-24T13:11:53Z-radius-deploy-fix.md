---
timestamp: 2026-03-24T13:11:53Z
session: radius-deploy-fix
---

# Session Log — Radius Deploy Fix

## Agents
- **Daisy** (Lead): Approved smallest fix for Dapr provisioning contract violations.
- **Graham** (Platform Dev): Implemented recipe-backed Dapr resources, OCI artifact publishing, and workflow integration.

## Critical Decision
Recipe-provisioned Dapr components in `app.bicep` must omit `type`, `version`, and `metadata` — these are derived from recipe invocation, not ad-hoc.

## Deliverables
- Fixed application model (app.bicep)
- Recipe publishing automation (publish-radius-recipes.sh)
- CI/CD integration (deploy-azure.yml)
- Validation checklist updated
- Cross-agent history reconciled

## Validation
- `rad deploy infra/radius/app.bicep` no longer fails on Dapr contract violations
- `az bicep build` and `dotnet test` passing
- Recipe artifacts reproducibly published to OCI registry

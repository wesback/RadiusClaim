# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Squad Roster (2026-03-23)

| Name | Role |
|------|------|
| Daisy | Lead |
| Billy | Backend Dev |
| Graham | Platform Dev |
| Karen | Tester |
| Eddie | Docs/Story |

All members drawn from "Daisy Jones & The Six" universe per user naming preference.

## Phase 1 Work (2026-03-23)

### Delivered

**Phase 1 Radius Platform Scaffold**
- Established platform root at `infra/radius/` with a clean separation from raw Kubernetes YAML.
- Created reusable `modules/container-service.bicep` for shared service deployment pattern (image, ports, environment variables).
- Stubbed environment parameter files:
  - `environments/dev.bicep` — local/emulator environment
  - `environments/prod.bicep` — Azure environment (stub for Phase 5+)
- Created `app.bicep` skeleton with three named services (`expense-api`, `workflow-engine`, `notification-svc`) as Radius containers.
- Added Dapr component placeholder structure: `dapr/statestore.yaml`, `dapr/pubsub.yaml`, `dapr/secrets.yaml` (functional configs deferred to Phase 2).
- Named services match Billy's Dapr app IDs exactly (kebab-case in Radius, PascalCase in .NET projects).

### Key Decisions

**Platform Control Plane:**
- Radius is the control plane for service wiring, not an orchestration wrapper around raw Kubernetes YAML.
- Environment-specific parameters live under `environments/` for predictable reuse.
- Azure recipes live under `recipes/azure/` (stubs until Phase 5 implementation).

**Port Convention:**
- Standard container port: 8080 (Dapr sidecar expects this from all services).

### Evidence

- `az bicep build --file infra/radius/app.bicep --outfile /tmp/cloudexpense-app.json` ✅ passed
- Phase 1 exit criteria 2, 9 confirmed

### Next Phase

Phase 2: Configure local dev environment (docker-compose, Dapr sidecar configs for state store, pub/sub, secrets).

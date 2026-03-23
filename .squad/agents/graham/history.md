---
last_updated: 2026-03-23T17:50:00Z
---

# Graham History

## Phase 3 Work (2026-03-23)

### Delivered

**Phase 3 Pub/Sub Infrastructure**
- Added `infra/dapr/local/pubsub.yaml` — Redis-backed pub/sub component for local development
- Scoped access to `workflow-engine` and `notification-svc` only
- Reused existing local Redis container from Phase 2 (`localhost:6379`)
- No authentication required for local development
- No changes to `infra/dapr/local/docker-compose.yaml` (Redis already present)

### Design Decision

Kept pub/sub as a development overlay under `infra/dapr/local/`, preserving the pattern where Radius owns service topology while local overlays provide development-only Dapr components. This prevents Radius from needing to model local-only infrastructure and makes the distinction between production wiring and local emulation clear.

### Validation

- Component YAML validated by Karen as part of Phase 3 exit criteria
- Properly scoped to workflow-engine and notification-svc
- Reusing existing Redis simplifies local environment setup

## Learnings

- Keep Dapr component names aligned with shared contract constants (`statestore`, `pubsub`) in both Radius resources and local overlays so app code never needs environment-specific aliases.
- For local-only Dapr backing services, colocate the component YAML and the minimal emulator runtime under `infra/dapr/local/` so the override is obvious without competing with the Radius application model.

- Reuse the existing local Redis container for both Dapr state and pub/sub overlays unless a phase explicitly needs isolation; it keeps Phase 3 wiring explainable and avoids duplicate local infrastructure.

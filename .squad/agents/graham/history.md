---
last_updated: 2026-03-23T15:00:00Z
---

# Graham History

## Learnings

- Keep Dapr component names aligned with shared contract constants (`statestore`, `pubsub`) in both Radius resources and local overlays so app code never needs environment-specific aliases.
- For local-only Dapr backing services, colocate the component YAML and the minimal emulator runtime under `infra/dapr/local/` so the override is obvious without competing with the Radius application model.

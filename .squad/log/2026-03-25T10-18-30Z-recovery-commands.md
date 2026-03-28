# Recovery Commands Session Log

**Date:** 2026-03-25  
**Author:** Graham (Platform Dev)  
**Phase:** 7 (Azure Deployment)

## Summary

Produced review-only live-cluster recovery command set for `radiusclaim-azure-radiusclaim` namespace.

## Outcome

Recommended execution path:
1. Add GHCR pull auth in namespace (`imagePullSecret` for `ghcr.io/wesback/radiusclaim`)
2. Redeploy expense-api, workflow-engine, notification-svc with explicit tags (prefer semver or git SHA, not `:latest`)
3. Verify Dapr components; if missing, redeploy Radius environment

## Key Notes

- Explicit tags preferred over `:latest`
- Dapr components are Radius-owned (not manual K8s manifests)
- `rad deploy` is idempotent; safe for recovery use
- Detailed commands in orchestration log + inbox decision document

## Status

Ready for team review and execution.

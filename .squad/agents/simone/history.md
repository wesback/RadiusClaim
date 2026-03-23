# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Learnings

- Added mid-stream to solve transaction/compensation issues in the Phase 2 expense submission path.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Own truthful failure semantics without expanding Phase 2 into workflow behavior.
- For shared Dapr index keys, track whether the current request actually inserted the ID before compensating, then re-check the record after rollback so concurrent creates resolve to `200/409` instead of a dishonest failure.

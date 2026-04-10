# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Learnings

- Added mid-stream to handle backend consistency and reliability revisions.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Own backend reliability fixes without expanding Phase 2 beyond expense-api and local state-store scope.
- When a portable list endpoint already filters missing records, indexing first and persisting the record second is safer than returning a failed submit after a hidden write.
- Read-after-write verification must not upgrade an ambiguous replay/concurrency outcome to `201 Created`; return an idempotent success only when the stored record already matches the requested payload.

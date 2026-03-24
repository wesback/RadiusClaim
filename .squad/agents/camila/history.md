# Camila History

## Core Context

- User: Wesley Backelant
- Project: RadiusClaim — Dapr + Radius reference sample
- Stack: .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure-backed platform story, planned web UI
- Mission: design and build a beautiful, modern frontend experience for the RadiusClaim application without weakening the portability story

## Learnings

- Added to the squad on 2026-03-24 as the dedicated frontend/UI specialist.
- Initial remit is to design a modern web interface for the expense submission and workflow visibility experience.
- Chose a hosted frontend inside `src/expense-api/wwwroot/app/` so the sample gains a polished UI without introducing a separate Node toolchain, CORS setup, or an extra deployment surface.
- Added a workflow-telemetry proxy at `GET /expenses/{id}/workflow` in `src/expense-api/Program.cs`; it derives the workflow instance from `ExpenseRecord.CorrelationId` and keeps the browser on the same origin.
- Key UI entry points now live at `src/expense-api/wwwroot/app/index.html`, `src/expense-api/wwwroot/app/styles.css`, and `src/expense-api/wwwroot/app/app.js`.

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
- Conducted framework landscape research (March 2026) evaluating React + Vite + TypeScript, Next.js, Vue, SvelteKit, and Blazor (WASM/Server) against RadiusClaim's constraints: same-origin hosting, Kubernetes-first portability, demo clarity, and long-term maintainability.
- **Decision**: Recommend React + Vite + TypeScript as primary choice, Vue + Vite as runner-up. Vanilla approach was the right demo-first decision but reaches its limits at scale (no type safety, monolithic state, no component reusability).
- Rationale for React: industry-standard job market (70%+ market share), mature ecosystem, excellent TypeScript support, Vite's fast HMR, ability to keep the app in `wwwroot/` without separate Node deployment, and component-based architecture makes the UI teachable.
- Migration path is non-breaking: create `src/expense-api/client/` as separate Vite project, build to `wwwroot/app/dist/`, no API changes, no deployment changes — still one .NET binary.

## Team Input (2026-03-24)

- **Daisy (Lead)** provided framework-fit analysis: Keep vanilla UI unless conditions change (UI becomes product, multiple routes needed, separate SPA deployment desired, or team composition shifts)
- Rationale: UI is demo surface, not product; framework adds pedagogical friction without advancing Dapr + Radius narrative
- **Implication for React recommendation:** Document React path for future reference; maintain vanilla JS as the appropriate choice for Phase 7
- **Status:** React recommendation is documented and ready for team; vanilla is the current path forward

## Learnings (Issue #15 — Monitoring Dashboard, 2026-03-27)

- Issue #15 asked for a workflow monitoring dashboard; the existing `wwwroot/app/` UI already covered items 1–3 (expense list with status, timeline/history, auto-refresh).
- The missing piece was approve/reject buttons for `ManualReviewRequested` expenses. Added `handleApproval()` in `app.js` that POSTs to `/expenses/{id}/approve` or `/expenses/{id}/reject`.
- Buttons appear inline in the workflow card only when `expense.status === "ManualReviewRequested"`, keeping the UI minimal and context-specific.
- Adjusted history polling from 10 s to 5 s to match the issue requirement.
- Used `--approve` / `--reject` CSS modifier classes styled with the existing `--success` / `--danger` CSS variables; no new design system tokens needed.
- Chose not to introduce a new `src/dashboard/` Next.js app — the existing vanilla UI in `wwwroot/app/` already satisfies all requirements with zero toolchain overhead.

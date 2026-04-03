---
name: "dotnet-hosted-demo-ui"
description: "Ship a polished demo UI from an existing ASP.NET Core service without adding a separate frontend stack"
domain: "frontend"
confidence: "high"
source: "camila-phase7"
---

## Context

Use this pattern when a .NET service needs a browser-facing demo surface, but the repo does not already have a frontend toolchain and the goal is speed, clarity, and portability.

## Patterns

### Host static assets from the existing web service

- Put the UI under `wwwroot/` so ASP.NET Core serves it natively.
- Give the UI a stable route like `/app` instead of replacing the API root.
- Keep the API descriptor or health endpoints intact to avoid breaking existing automation.

### Prefer same-origin integration over frontend sprawl

- If the UI needs data from multiple backend services, add a narrow server-side proxy endpoint in the host service instead of introducing CORS and a second deployment path.
- Reuse existing identifiers already present in the domain model (for example, `CorrelationId` as the workflow instance key).

### Optimize for demo legibility

- Build the UI around the actual walkthrough: submit, observe status changes, explain outcomes.
- Surface trace identifiers and workflow summaries directly in the UI so presenters do not need to cross-reference raw JSON.
- Add sensible polling so the async flow feels alive without needing websockets.

## Examples

- `src/expense-api/wwwroot/app/index.html`
- `src/expense-api/wwwroot/app/styles.css`
- `src/expense-api/wwwroot/app/app.js`
- `src/expense-api/Program.cs` (`GET /expenses/{id}/workflow`, `/app`)

## Anti-Patterns

- Spinning up a new SPA stack just to render one demo page
- Moving the entire backend behind a frontend-specific API shape
- Replacing the API root and breaking existing CLI docs or validation scripts

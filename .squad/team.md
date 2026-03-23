# Squad Team

> CloudExpense Lite — Dapr + Radius reference sample

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Daisy | Lead | `.squad/agents/daisy/charter.md` | ✅ Active |
| Billy | Backend Dev | `.squad/agents/billy/charter.md` | ✅ Active |
| Graham | Platform Dev | `.squad/agents/graham/charter.md` | ✅ Active |
| Karen | Tester | `.squad/agents/karen/charter.md` | ✅ Active |
| Eddie | Docs/Story | `.squad/agents/eddie/charter.md` | ✅ Active |
| Scribe | Session Logger | `.squad/agents/scribe/charter.md` | 📋 Silent |
| Ralph | Work Monitor | — | 🔄 Monitor |

## Coding Agent

<!-- copilot-auto-assign: false -->

| Name | Role | Charter | Status |
|------|------|---------|--------|
| @copilot | Coding Agent | — | 🤖 Coding Agent |

### Capabilities

**🟢 Good fit — auto-route when enabled:**
- Bug fixes with clear reproduction steps
- Test coverage additions and flaky test fixes
- Small isolated features with explicit acceptance criteria
- Boilerplate, scaffolding, and README polish

**🟡 Needs review — route to @copilot but require squad review:**
- Medium implementation tasks with a clear spec
- Refactoring that follows established patterns
- Endpoint additions that stay inside existing service boundaries

**🔴 Not suitable — keep with squad members:**
- Architecture decisions and system design
- Security-critical changes or auth design
- Cross-service Dapr/Radius integration decisions
- Ambiguous work that needs product or platform trade-offs

## Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Description:** A small, reference-quality expense filing sample that demonstrates portable app patterns with Dapr in the app layer and Radius in the platform layer.
- **Created:** 2026-03-23
- **Issue Source:** Not connected yet

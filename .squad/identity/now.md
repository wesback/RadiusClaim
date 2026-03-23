---
updated_at: 2026-03-23T17:11:21Z
focus_area: Phase 7 — End-to-end Radius validation, docs, integration tests
active_issues: []
phase: 7-in-progress
---

# What We're Focused On

**Phases 1–6 COMPLETE and approved. Radius-first redesign COMPLETE and approved. Phase 7 now in progress.**

## Current Achievement Summary

All application code (Phases 1–4) and platform wiring (Phases 5–6) are complete, integrated, and validated.

### App Code Track (Phases 1–4) — ✅ COMPLETE

- Phase 1: Contracts and scaffold — foundational types defined
- Phase 2: Expense API with Dapr state — end-to-end CRUD working
- Phase 3: Workflow orchestration with pub/sub — full approval flow proven
- Phase 4: Notification subscriber — end-to-end message delivery validated

**Dapr building blocks proven:** State, Workflows, Pub/Sub, Service Invocation. (Secrets deferred; Bindings out of scope.)

### Platform Track (Phases 5–6) — ✅ COMPLETE

- Phase 5: Local Radius integration — environment definitions and real Azure recipes
- Phase 6: Azure Container Apps deployment — CI/CD workflow with end-to-end validation on live Azure

**Platform portability:** Same app code on local Kubernetes and Azure. Dapr component names stable across all paths.

### Radius-First Redesign — ✅ COMPLETE & APPROVED

Layer separation complete:
- **Layer 1 (Azure Bootstrap):** Minimal cloud-specific resources (ACR, ACA env, identity, Log Analytics)
- **Layer 2 (Radius Deployment):** App services, Dapr components, Azure recipes

**Primary command:** `rad deploy infra/radius/app.bicep`
**Fallback (explicit):** Azure Container Apps CI/CD path (demoted, honest about Radius compute gap)
**Status:** Approved by Karen (2026-03-23T19:10:00Z)

### Portability Fixes — ✅ COMPLETE & APPROVED

- Graham's parameterization: `app.bicep` uses overrideable `daprBackings` object; logical component names stay stable
- Eddie's documentation: README clearly separates app portability (Dapr + code) from infrastructure reality (Azure-specific today, Radius-intended)
- Karen approved both fixes: portability story now credible without overstating

## Phase 7 Scope — In Progress

**Remaining work to finalize the sample:**

1. **End-to-end Radius validation** — When team has live Radius environment, run $50 and $150 expense flows through `rad deploy` path with full traceability
2. **Documentation & demo scripts** — Update README with clear Radius-first narrative, add step-by-step demo walkthrough, document GitHub Actions secrets/variables
3. **Integration test suite** — Optional but recommended: automated tests covering the full flow (or at minimum, a checklist script)
4. **ADR documentation** — Explain why Azure CLI was necessary interim workaround, what changes when Radius adds ACA support

**Non-goals for Phase 7:**
- App code changes (app is done)
- Platform redesign (Radius-first pattern is settled)
- Multi-cloud support (Azure-only for this sample)
- Secrets population (component exists for completeness; not used in demo flow)

## Demo Capability (Now Executable)

A presenter can now run the full Radius-first expense journey:

1. **Local development:** Run full expense flow with local Kubernetes and Dapr (Phases 1–4 app code)
2. **Radius validation:** Deploy to Kubernetes with Azure recipes via `rad deploy` (Phase 5 patterns)
3. **Azure deployment:** Push to Azure Container Apps with full validation (Phase 6 CI/CD)
4. **Portability story:** "Same app code, different infrastructure backing, wired by Radius"

All three paths use identical app code and same logical Dapr component names. The story is:
> "Dapr keeps the app portable. Radius declares what services connect to and where they run. When you change clouds, you swap recipes and environment definitions—the app doesn't change."

## Five Dapr Building Blocks — Proven

1. ✅ **State** — Expense records persisted with optimistic concurrency
2. ✅ **Workflows** — Approval orchestration with branching and activity composition
3. ✅ **Pub/Sub** — Notification events published and consumed end-to-end
4. ✅ **Service Invocation** — Expense-api → workflow-engine fire-and-forget
5. ⏳ **Secrets** — Component modeled; population/usage deferred (Phase 7+)

## Next Steps

- **Phase 7 execution:** Team runs end-to-end validation of live Radius environment, finalizes documentation
- **Sample release:** After Phase 7, the sample is complete and ready for external sharing as a reference for Dapr + Radius portability patterns
- **Pattern library:** This sample becomes the foundation for future Dapr/Radius reference implementations (multi-service, multi-cloud, advanced patterns)

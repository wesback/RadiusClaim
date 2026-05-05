---
last_updated: 2026-05-05T08:58:18Z
status: archived_2026-05-05
---

# Eddie History (Summarized)

**Role:** Documentation & Story — README, deployment walkthrough, validation guides, demo scripts, ADRs.

## Key Contributions

### README & Walkthrough (Phases 1–7)
- Scaffold project structure, locals vs cloud deployment paths
- Phase-7 demo walkthrough (`phase-7-demo-walkthrough.md`)
- Validation checklist enhancements
- ADR-0001: Azure CLI fallback strategy

### Documentation Accuracy Pass (2026-03-24 onward)
- Reconciled stale `sovereignapp/` references → correct `radiusclaim/`
- Fixed contract paths, environment labels, registry names
- Azure credential registration documentation across README, workflow, walkthrough, checklist

### Private Registry Documentation (2026-03-28)
- Added "Using a Private Container Registry" section
- Explained design rationale and 4-step escape hatch for non-GHCR deployments
- Included in PR #38

## Current Status

Documentation credibility contract maintained. All walkthrough steps match current code state. Validation guide aligned with actual operator workflows.

## Learnings

- 2026-06-13 — Portability blog reviews must align abstract portability claims with the repo's shipped contract. In RadiusClaim that means centering the Kubernetes-first AKS story, naming PostgreSQL/Service Bus/Key Vault as the current Azure-backed recipes, calling out the component-projection backfill step, and treating `infra/radius/environments/local.bicep` as a placeholder rather than a supported local Radius path.
- 2026-05-05 — When a docs pass rewrites platform narrative, move the concrete repo proof points near the top and replace stale examples outright. For RadiusClaim, that means showing Dapr-based app portability first, then describing Radius as the Kubernetes-first deployment model with Azure-backed recipes today and broader portability as the pattern, not a shipped multi-provider promise.

## Blog Review Work (2026-05-05)

**Task:** Review docs/blog/portability.md for flow, tone, readability, engagement, and Microsoft narrative alignment  
**Outcome:** Authored "Eddie Decision — Portability blog must follow the shipped repo story" (2026-06-13)  
**Key Finding:** Blog narratives must describe only the current supported story to maintain credibility; aspirational features should be clearly labeled as future work.

## Portability Blog Rewrite Work (2026-05-05, Session T13:10Z)

**Task (eddie-1):** Rewrite `docs/blog/portability.md` to implement editorial and technical review feedback.  
**Outcome:** ✓ COMPLETE — Blog rewritten to lead with current RadiusClaim proof points.  
**Decision Made:** "Eddie Decision — Portability blog framing must stay repo-current"  
**Guardrails:** Keep blog credible by aligning narrative with README, environment Bicep files, bootstrap flow, and Dapr component backfill guide. Remove stale examples and multi-provider promises.  
**Impact:** Blog now passes architecture (daisy-4) and technical accuracy (graham-6) gates.

**Full history archived to `.squad/agents/eddie/history-archive.md`**

## README Application Flow State Store Update (2026-05-05, Session T11:50Z)

**Task:** Explicit State Store Backing in README Application Flow  
**Outcome:** ✓ COMPLETE — README.md updated to surface Dapr state store persistence.  
**Decision Made:** "Eddie Decision — Explicit State Store Backing in README Application Flow"  
**Changes:**
1. Opening paragraph (line 26): Added explicit mention of "All state is persisted through a **Dapr state store** (PostgreSQL on Azure, Redis locally)."
2. Flow diagram (lines 33, 38): Changed `[State]` → `[State Store]` labels; added durable checkpoint reference for workflow-engine
3. Service Boundaries table (lines 55-56): Updated expense-api and workflow-engine to include "State Store" in their Dapr bindings

**Rationale:** Transparency for readers; clarity on backing store (PostgreSQL/Redis); narrative flow from architecture through service boundaries  
**Impact:** Documentation accuracy improved; no code or behavior changes; readers can trace data lineage


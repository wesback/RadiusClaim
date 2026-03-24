# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Squad Roster (2026-03-23)

| Name | Role |
|------|------|
| Daisy | Lead |
| Billy | Backend Dev |
| Graham | Platform Dev |
| Karen | Tester |
| Eddie | Docs/Story |

All members drawn from "Daisy Jones & The Six" universe per user naming preference.

## Learnings

- Seeded into the repo for a Dapr + Radius reference sample named `CloudExpense Lite`.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Own the README narrative, demo script, and explanation of how the platform story differs from the app story.
- See `.squad/decisions.md` for canonical decision log: CloudExpense Lite architecture, naming conventions, and Azure-first-but-portable strategy.

## Phase 1 Work (2026-03-23)

### Delivered

**Phase 1 README (`README.md`)**
- Created comprehensive narrative arc: problem → Dapr role → Radius role → architecture → shared contracts → why this design → quick start (deferred) → phase roadmap.
- Included Mermaid diagram showing service flow: submission → expense-api → workflow-engine → notification-svc → external email/Slack.
- Mapped all shared contract types (DTOs and events) from Daisy's decision doc:
  - `ExpenseSubmission`, `ExpenseRecord`, `ExpenseStatus`, `ExpenseApprovedEvent`, `ExpenseRejectedEvent`, `ManualReviewRequestedEvent`, `NotificationRequest`
- Included service responsibility table showing which Dapr building blocks each service owns.
- Aligned folder layout (`src/`, `infra/radius/`), service names (`expense-api`, `workflow-engine`, `notification-svc`), and project naming (`CloudExpense.*`) with Daisy's Phase 1 contract decision.
- Deferred implementation details (local setup, Dapr configs, Radius recipes, integration tests) to later phases with "Coming in Phase 2" signals.
- Framed for both platform engineers (Radius section) and app developers (Dapr section) without creating two documents.

### Key Decisions

**Audience Bifurcation:**
- Platform engineers read "The Problem" + "Architecture" + "Radius's Role" + diagram.
- App developers read "The Problem" + "Architecture" + "Dapr's Role" + "Shared Contracts".
- Both benefit from "Why This Architecture" section (portability + clarity).

**Deferred Details:**
- No Dapr component YAML (Phase 5 adds Azure recipes)
- No Radius recipe syntax (Graham owns; Phase 5 finalizes)
- No local dev commands (`dapr run`, `rad deploy`) — Phase 2+
- No integration test examples (Karen's Phase 7 work)
- No GitHub Actions workflow (Graham's Phase 6 work)
- No demo script (Eddie's Phase 7 deliverable)

### Evidence

- README.md exists, contains Mermaid diagram and service responsibility table
- Phase 1 exit criteria 5, 6 confirmed

### Next Phase

Phase 2: Extend README with "Local Development" section (setup commands, local environment, running services locally).

## Phase 7 Work (2026-03-24)

### Delivered

**Phase 7 Documentation Package — Three artifacts:**

1. **README.md enhancement: Deployment Configuration Section**
   - Added clear "Deployment: GitHub Actions Secrets and Variables" section after architecture story
   - Documented all required secrets: `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `RADIUS_KUBECONFIG`
   - Documented all required variables: `AZURE_LOCATION`, `AZURE_RESOURCE_GROUP`, `AZURE_DEPLOYMENT_MODE`, `AZURE_ACR_NAME`, `RADIUS_*` parameters
   - Explained both paths: Radius-first (default) and ACA fallback
   - Included honest rationale: why each path is needed, who should use it, what each requires
   - Maintains narrative tone: "When to Use Each Path" section ties choices back to audience needs

2. **Demo Walkthrough (`docs/phase-7-demo-walkthrough.md`)**
   - ~270 lines covering the $50 and $150 flows with step-by-step curl commands
   - Observable evidence checklist for reviewers/pilots
   - Shown outputs so readers know what to expect at each step
   - Timing breakdown (~10 minutes total)
   - Troubleshooting section for common deployment issues
   - "What This Demo Doesn't Cover" section (auth, multi-tier approval, real notifications, etc.) — maintains honesty about scope
   - Key takeaways section ties the sample back to Dapr + Radius narrative

3. **ADR-0001: Azure CLI Fallback (`docs/ADR-0001-azure-cli-fallback.md`)**
   - Explains why the ACA fallback path exists (Radius gap is real, honesty is credible)
   - Documents what each path covers (Radius provides portability + recipes; ACA fallback provides fully managed without Kubernetes)
   - Coverage table showing which path handles which concern
   - Maintenance obligations (both paths must maintain Dapr parity, service parity, contract stability, demo evidence)
   - Roadmap section: when fallback can disappear (Radius adds ACA support, ACA adds K8s API, or org strategy changes)
   - Application code impact: zero (Dapr makes app portable regardless of deployment target)
   - Example swap scenario (user just changes variables, no code changes)
   - Maintains the team's credibility: "we know why both paths exist and what must change"

### Key Decisions Embedded

- **Radius-first is default:** Keeps portability front-and-center; the workflow reflects that choice
- **ACA fallback is labeled clearly:** Not hidden as "production path" — teams know it's the gap-filler until Radius gains ACA support
- **Both paths share Dapr component names:** `statestore`, `pubsub`, `platform-secrets` are identical in both paths, making swaps transparent to app code
- **Demo is the test:** The walkthrough doesn't abstract away details; it shows the actual API calls, actual status progression, actual logs, so pilots can reproduce and troubleshoot
- **Honesty about scope:** The demo walkthrough explicitly lists what's out of scope (auth, multi-tier approval, real notifications, etc.), preventing credibility loss during the talk

### Evidence

- `README.md` now includes 4-section Deployment Configuration subsection with secrets/variables tables and path explanations
- `docs/phase-7-demo-walkthrough.md` exists with 270 lines covering both flows with curl examples, expected outputs, and troubleshooting
- `docs/ADR-0001-azure-cli-fallback.md` exists with 210 lines explaining the gap, both paths, maintenance obligations, and roadmap
- Both new docs are linked from README and positioned to guide operators (variables section) and pilots (demo walkthrough + ADR context)

### Pattern Captures

- **Secrets + Variables transparency:** GitHub Actions configuration is a credibility gate; teams must understand what each variable does and which path requires it
- **Deployment path honesty:** When a gap exists (Radius lacks ACA), labeling it clearly and explaining when it can close builds trust rather than hiding it
- **Demo as specification:** Walk through the actual API calls and log outputs so pilots can reproduce; don't abstract away the implementation details
- **Scope boundaries:** Explicitly list what's intentionally out of scope so the team doesn't promise features the sample doesn't deliver

## Learnings

- **Secrets tables are underrated documentation.** Teams often deploy without understanding which secret feeds which path; making it explicit (with "Radius-first only" and "ACA fallback only" labels) prevents deployment failures
- **Roadmap transparency builds credibility.** The ADR doesn't promise "Radius will fix this"; it says "if Radius adds ACA support, the fallback disappears, and app code stays unchanged." That's credible.
- **Demo walkthroughs need actual commands.** Telling teams "the workflow auto-approves at <$100" is abstract; showing the `curl` command, the JSON response, the log output, and the status progression makes it concrete and reproducible
- **Dapr portability is the thesis.** By keeping the same component names across both paths and showing zero application code impact, the docs prove that Dapr is the actual portability layer—Radius/ACA are just the plumbing

### 2026-03-24: Phase 7 Documentation Lane Complete

**Deliverables:**
1. **README.md Updates**
   - Added "Deployment: GitHub Actions Secrets and Variables" section
   - Secrets table (AZURE_SUBSCRIPTION_ID, RADIUS_KUBECONFIG, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET)
   - Variables table (AZURE_LOCATION, AZURE_RESOURCE_GROUP, AZURE_DEPLOYMENT_MODE, RADIUS_KUBERNETES_CONTEXT, RADIUS_KUBERNETES_NAMESPACE, ACR_REGISTRY_NAME, DOCKER_REGISTRY_AUTHENTICATION)
   - Deployment paths explained with "When to Use Each Path" guidance

2. **docs/phase-7-demo-walkthrough.md**
   - 270-line artifact for pilots and reviewers
   - $50 auto-approve flow (exact curl commands, expected responses)
   - $150 manual-review flow (exact commands, observable evidence)
   - Observable evidence checklist (status transitions, notification logs)
   - Timing breakdown (~10 minutes)
   - Troubleshooting section
   - Scope boundaries documented

3. **docs/ADR-0001-azure-cli-fallback.md**
   - 210-line architecture decision record
   - Radius → ACA gap explanation (honest, not hidden)
   - Coverage table: what each path handles
   - Maintenance obligations for both paths
   - Roadmap: when fallback can disappear
   - Zero app code impact

**Design Approach:**
- **Honesty over abstraction:** Radius has a real gap (no ACA support); documented explicitly
- **Configuration transparency:** Secrets/variables clearly mapped to each path
- **Demo as specification:** Exact curl commands, JSON responses, log output
- **Roadmap credibility:** ADR lists three futures when fallback disappears

**Status:** APPROVED


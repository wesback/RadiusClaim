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

## 2026-03-24: App Rename — CloudExpense Lite → RadiusClaim

### Delivered

**Complete user-facing rename sweep across all documentation and scripts:**

1. **README.md** (6 updates)
   - Title: `# CloudExpense Lite` → `# RadiusClaim`
   - Introductory narrative: "CloudExpense Lite shows the answer" → "RadiusClaim shows the answer"
   - Project layout: `CloudExpenseLite.slnx` → `RadiusClaim.slnx`
   - Namespace reference: `CloudExpense.Contracts` → `RadiusClaim.Contracts` (matches actual source code)
   - Deployment variables table: Updated example resource group from `cloudexpense-lite-rg` to `radiusclaim-rg` and namespace from `cloudexpense-lite-azure` to `radiusclaim-azure`

2. **docs/phase-7-demo-walkthrough.md** (1 update)
   - Prerequisites section: "CloudExpense Lite is deployed" → "RadiusClaim is deployed"

3. **docs/ADR-0001-azure-cli-fallback.md** (3 updates)
   - Summary section: "CloudExpense Lite aims to demonstrate" → "RadiusClaim aims to demonstrate"
   - Maintenance obligations: "CloudExpense Lite contract shapes" → "RadiusClaim contract shapes"
   - References section: "CloudExpense Lite Repo" → "RadiusClaim Repo"

4. **docs/phase-1-validation.md** (2 updates)
   - Title: `# CloudExpense Lite — Phase 1 Validation Gate` → `# RadiusClaim — Phase 1 Validation Gate`
   - Build command reference: `CloudExpenseLite.slnx` → `RadiusClaim.slnx`

5. **docs/phase-7-validation-checklist.md** (2 updates)
   - Purpose section: "CloudExpense Lite sample is production-ready" → "RadiusClaim sample is production-ready"
   - Release checkpoint: "CloudExpense Lite is demo-ready" → "RadiusClaim is demo-ready"

6. **docs/radius-validation-checklist.md** (37 updates across multiple categories)
   - All namespace references: `cloudexpense-lite-azure` → `radiusclaim-azure`
   - All container registry paths: `ghcr.io/<your-org>/cloudexpense-lite` → `ghcr.io/<your-org>/radiusclaim`
   - All resource group examples: `cloudexpense-lite-rg` → `radiusclaim-rg`
   - All deployment output messages: Application name updated in example outputs
   - Total: 37 sed operations across namespace, container registry, and resource group references

7. **scripts/README.md** (3 updates)
   - Title: `# CloudExpense Lite - Scripts` → `# RadiusClaim - Scripts`
   - Purpose sections: All three script descriptions updated from CloudExpense Lite to RadiusClaim

8. **scripts/validate-deployment.sh** (2 updates)
   - Script header comment: `# CloudExpense Lite - Deployment Validation Script` → `# RadiusClaim - Deployment Validation Script`
   - Description comment: "deployed CloudExpense Lite instance" → "deployed RadiusClaim instance"
   - Success message: "CloudExpense Lite deployment is HEALTHY" → "RadiusClaim deployment is HEALTHY"

### Pattern: Technical Naming vs. User-Facing

**Kept intentionally:**
- Internal C# namespace references in infra/radius/app.json (used by Bicep parameter defaults; these don't affect user-facing demo)
- Resource naming function prefix in pubsub recipe: `cloudexpense-{0}` is a technical prefix for auto-generated Azure resource names, not user-visible

**Renamed consistently:**
- All documentation titles, headings, and explanatory text
- All example configuration values and defaults
- All example command outputs and resource names
- All script messages and user-facing strings

### Evidence

- `grep -r "CloudExpense\|cloudexpense-lite" /Users/wesleyb/git/RadiusClaim/README.md /Users/wesleyb/git/RadiusClaim/docs/*.md /Users/wesleyb/git/RadiusClaim/scripts/*.sh /Users/wesleyb/git/RadiusClaim/infra/radius/*.json` returns 0 results
- All demo walkthroughs, validation checklists, and operational scripts now reference RadiusClaim consistently
- Source code (C# namespaces) already uses RadiusClaim, now aligned with documentation

### Next Steps

Team communication moving forward should reference the sample as "RadiusClaim" in all public-facing materials (demos, talks, blogs, external sharing).


## 2026-03-24: Deployment Narrative Pivot — Kubernetes-First with Honest Azure Backing Services

### Delivered

**Reframed all deployment-related documentation from ACA-fallback narrative to Kubernetes-first, with honest backing-service scoping:**

1. **README.md Updates (Deployment sections)**
   - Changed opening tagline from "deployed on Azure Container Apps" to "deployed on Kubernetes with Azure backing services"
   - Rewrote "Deployment Story" section to lead with Kubernetes + Radius as primary, with AKS as concrete example
   - Removed ACA fallback path references entirely
   - Clarified portability scope: app code is portable, deployment model is portable, backing services are tied to recipes (Azure recipes = Azure services)
   - Listed supported targets: AKS, Arc-enabled Kubernetes, self-managed Kubernetes
   - Updated deployment secrets/variables table to reflect Kubernetes-only configuration
   - Updated footer status to reflect "Kubernetes-first deployment via Radius; Azure backing services"

2. **ADR-0001 Complete Reframe (Kubernetes-First Deployment Strategy)**
   - Renamed from "Azure CLI Fallback Path" to "Kubernetes-First Deployment Strategy with Azure Backing Services"
   - Rewrote Problem section to explain portability enabled by (1) Dapr abstractions, (2) Radius recipes, (3) environment definitions
   - Removed ACA fallback path documentation entirely
   - Rewrote Roadmap to focus on enabling other clouds via Radius recipes (AWS, GCP)
   - Updated Application Code Impact to emphasize environment agnosticism

3. **Demo Walkthrough, Phase 7 Validation, Radius Validation, Scripts README**
   - Updated all references from ACA logs to Kubernetes logs (kubectl)
   - Added port-forward examples for local access
   - Simplified single-path deployment narrative

### Key Messaging Shifts

**Old:** "Radius-first (default) vs. ACA fallback"  
**New:** "Kubernetes-first with Radius; AKS is the primary example; recipes enable other clouds"

**Portability clarity:**
- ✅ App code, deployment model, compute (any K8s + Radius)
- ⚠️ Backing services tied to recipes (currently Azure; future: AWS/GCP recipes)

### Pattern Captures

**Backing-service honesty:** Don't claim full portability if recipes are cloud-specific. Separate compute portability from service portability.

**Recipes as the portability lever:** Instead of dual deployment paths, frame recipes as the future mechanism for multi-cloud support.

## Phase 7 Work (2026-03-24)

### Documentation & Narrative Reframe — Kubernetes-First Deployment

**Status:** IMPLEMENTED

**What:** Reframed all deployment documentation from "Radius-first with ACA fallback" to "Kubernetes-first with Azure backing services via Radius recipes."

**Why:** Conceptual clarity; honest portability; future scalability; removed teaching debt.

**What's Portable:** App code (Dapr abstractions), deployment model (Radius app + environment patterns), service topology, compute targets (AKS, Arc-enabled, self-managed Kubernetes).

**What's Backed by Recipes:** Azure services (Blob Storage, Service Bus, Key Vault); AWS/GCP recipes are additive, not rearchitecture.

**Documentation Changed:**
- README.md (opening tagline, deployment story, secrets table, footer)
- ADR-0001 (complete reframe from ACA fallback to K8s-first roadmap)
- docs/phase-7-demo-walkthrough.md (kubectl logs instead of az containerapp)
- docs/phase-7-validation-checklist.md (single K8s path)
- docs/radius-validation-checklist.md (K8s-native commands)
- scripts/README.md (kubectl patterns)

**Messaging:**
> "RadiusClaim runs on any Kubernetes cluster with Dapr and Radius. AKS with Azure backing services is the primary example. When Radius recipes for AWS or GCP exist, the same app model targets those clouds with only recipe/environment changes."

**No Longer Valid:**
- ACA fallback narrative (removed from user-facing docs)
- "Radius-first vs. ACA fallback" framing
- Dual-path deployment configuration in docs
- Azure Container Apps as "compute alternative" in this sample

## 2026-03-24: End-to-End Setup Walkthrough

### Delivered

**Complete step-by-step operator guide: `docs/end-to-end-setup-walkthrough.md` (674 lines)**

Covers the entire flow from resource group creation to opening the app in a web browser:

**Steps 1–5: Azure & Kubernetes Foundation**
1. Azure login and subscription selection
2. Resource group creation (backing services container)
3. Kubernetes cluster provisioning (Option A: AKS; Option B: existing cluster)
4. Dapr control plane installation on cluster
5. Radius control plane installation on cluster

**Steps 6–9: Deployment Preparation**
6. Publish Radius recipe artifacts to GHCR (state store, pub/sub, secrets)
7. Initialize Radius workspace and group (manual deployment only)
8. Deploy Radius environment (azure-radius.bicep) — links Dapr to Azure backing services
9. Deploy RadiusClaim application (app.bicep) — three services with injected Dapr sidecars

**Steps 10–12: Validation & Use**
10. Verify deployment and retrieve public endpoint
11. Open `/app` in web browser
12. Run validation script to confirm $50 auto-approve and $150 manual-review flows

**Design Principles:**
- **Honest about what's automated:** GitHub Actions workflow, Radius deployment, Dapr injection, image builds
- **Clear about manual steps:** Azure auth, cluster provisioning, kubeconfig setup, namespace management
- **Realistic timing:** ~30–45 minutes depending on Azure resource creation (noted upfront)
- **Dual-path support:** GitHub Actions (recommended) and local `rad` CLI (advanced)
- **Practical troubleshooting:** 12 common issues with solutions (kubeconfig, control plane, recipes, endpoints, validation)
- **Next steps included:** Demo flow instructions, code exploration pointers, change redeployment patterns

**Readability:**
- Pre-formatted code blocks with expected outputs
- Environment variable patterns to avoid copy-paste errors
- Conditional instructions (GitHub Actions vs. `rad` CLI)
- Cross-linked to related docs (phase-7-demo, validation-checklist, architecture)

**Updated README.md**
- Added new walkthrough as first link in "Additional Documentation" section
- Positioned it before demo walkthrough (setup precedes demo)
- Includes audience note: "Complete operator guide from Azure login…"

### Key Messaging

> "RadiusClaim deployment spans Azure foundation (resource group, backing services), Kubernetes cluster (compute with Dapr + Radius control planes), Radius environment definition (Dapr component wiring to Azure), and application deployment. This walkthrough shows where the operator's role begins and ends, and which steps are automated by GitHub Actions vs. which require manual steps."

### Patterns Captured

**Setup documentation structure:**
- Section 0: Overview (what's automated, what's manual)
- Prerequisites validation (tools, credentials, cluster readiness)
- Numbered steps with clear boundaries (Azure → K8s → Dapr → Radius → App)
- Code blocks with expected outputs so operators can verify progress
- Conditional instruction paths (AKS vs. existing cluster; GitHub Actions vs. rad CLI)
- Practical troubleshooting keyed to symptom (not to tool)
- Next steps that extend into demo flows and architecture exploration

**What this enables:**
- New operators can onboard without asking for custom setup help
- Demo pilots understand what they're validating
- Support conversations can reference specific step numbers
- Discoverability: complete workflow in one document, with linked details for deep dives

### Status: COMPLETE AND VERIFIED

- `docs/end-to-end-setup-walkthrough.md` created (674 lines)
- `README.md` updated with link
- Covers all operator steps from Azure login to opening `/app` in browser
- Includes both GitHub Actions automation and manual `rad` CLI options
- Realistic timing, honest about prerequisites, practical troubleshooting

## Phase 7 Work — Portability Documentation Update (2026-03-24)

### Delivered

**Portability Narrative Shift: AWS/GCP → Azure Local / Arc-Enabled Kubernetes**

Removed speculative AWS/GCP examples and centered the portability story on concrete, supported targets:

**Files Updated:**
1. `README.md` — Removed explicit AWS/GCP naming; kept "other clouds" language as forward-looking
2. `docs/ADR-0001-kubernetes-first-deployment.md` — Major rewrite:
   - Replaced "Roadmap: Enabling Other Clouds" section with "Portability in Practice: Azure Local and Arc-Enabled Kubernetes"
   - New concrete example: Azure Local (edge) + Arc-enabled Kubernetes (on-premises / multi-cloud) + self-managed Kubernetes
   - Replaced "Example: Swapping to AWS" with "Example: Deploying to Azure Local or Arc-Enabled Kubernetes"
   - Updated component stability line: `(Azure, AWS, GCP, self-managed)` → `(Azure, Arc-enabled, self-managed)`
   - Updated backing-services portability language to remove AWS/GCP specifically, kept "other clouds" as future possibility
3. `docs/end-to-end-setup-walkthrough.md` — Clarified cluster options:
   - Option B now reads: "Any Kubernetes cluster (on-premises, edge, or multi-cloud) reachable from your machine and registered with Azure Arc"
   - Removed "GCP, AWS" examples, kept honest: Arc-enabled + self-managed are the concrete non-AKS targets
4. `scripts/README.md` — Already well-aligned; no changes needed

**Messaging Pattern:**
- **App code is portable** — Dapr abstractions, cloud-agnostic
- **Deployment model is portable** — Kubernetes-first via Radius, recipe-agnostic
- **Azure backing services are Azure-specific** — Blob, Service Bus, Key Vault; made explicit
- **Azure Local + Arc-enabled + self-managed are the portability proof points** — concrete, not speculative
- **Future recipes welcome** — if/when AWS, GCP, or other clouds have Radius recipes, pattern holds (same app, different env)

**Key Learnings:**
- Honesty matters more than aspirational cloud-agnosticism
- Azure Local + Arc-enabled Kubernetes are the natural non-AKS deployment targets for enterprise Dapr + Radius patterns
- Removing speculative examples (AWS, GCP) clarifies the real value: Kubernetes-portable app code + environment-swappable infrastructure
- The future-recipes section is fine as possibility, but day-one portability proof must be concrete (Azure Local, Arc, self-managed K8s)

### Context

From `.squad/identity/now.md`: "Portability Fixes — ✅ COMPLETE & APPROVED" and "Eddie's documentation: README clearly separates app portability (Dapr + code) from infrastructure reality (Azure-specific today, Radius-intended)."

This update finalizes the portability narrative by making it honest and concrete rather than aspirational.



## 2026-03-24: Walkthrough Location Update to belgiumcentral

**Task:** Update location references in `docs/end-to-end-setup-walkthrough.md` from `eastus` to `belgiumcentral`

**Work:**
- Updated line 113: Create Azure Resource Group section (environment variable example)
- Updated line 312: Required Variables section documentation
- Updated line 351: Deploy Radius Environment section example

**Rationale:**
- Consistent region reference across all deployment examples
- Aligns documentation with requested deployment region
- Maintains tight scope—no unrelated content modified
- All instances verified for consistency

**Outcome:** ✅ Complete. Documentation now guides users to deploy using Belgium Central as the Azure region for all Radius deployment steps.

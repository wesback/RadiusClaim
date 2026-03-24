# Eddie History — Documentation & Story

**Role:** Docs/Story — README, deployment walkthrough, validation guides, demo scripts, ADRs.

## Core Context

**Phases 1–7 Summary:**
- **Phase 1:** README scaffold with project summary, repo structure, locals vs cloud paths
- **Phase 2–4:** Incremental README updates as phases complete (contracts, state, workflows, pub/sub, notification, Azure)
- **Phase 5–6:** Phase-7 demo walkthrough (`phase-7-demo-walkthrough.md`), validation checklist enhancements, ADR-0001 for Azure CLI fallback
- **Phase 7:** Comprehensive documentation sweep: README accuracy, walkthrough clarity, validation checklist completeness, GitHub secrets/variables table, demo narrative truthfulness
- **2026-03-24:** Critical findings from Daisy's full-codebase audit: stale `sovereignapp/` name, wrong Contracts path, mislabeled `dev.bicep`, "Coming in Phase 2" text, stale registry names. Eddie assigned to reconciliation pass. Completed Azure credential registration documentation across README, workflow, walkthrough, checklist.

**Key Pattern:** Documentation is the credibility contract. Stale docs undermine demo trust. Walkthrough must exactly match code state. Validation guide must match what operators actually need to do.

---

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

## Phase 8 Work — AKS Walkthrough Documentation Fix (2026-03-24)

### Delivered

**Fixed Azure CLI Flag Error in End-to-End Setup Walkthrough**

**File:** `docs/end-to-end-setup-walkthrough.md` (Line 150)  
**Change:** `--enable-cluster-autoscaling` → `--enable-cluster-autoscaler`

**Problem:** The walkthrough documented an incorrect Azure CLI flag for the `az aks create` command. If users copied the command exactly, the CLI would reject it with an "unrecognized argument" error.

**Verification:** Scanned entire file; no remaining incorrect occurrences of the autoscaler flag pattern.

**Impact:** Operators following the walkthrough will now encounter no syntax errors when provisioning AKS clusters. Command references are now accurate against Azure CLI documentation.

### Status: COMPLETE

---

## Phase 9 Work — Docker Build Architecture Awareness (2025-01-16)

### Delivered

**Made Docker Build Guidance Architecture-Aware for Mac ARM Users**

**File:** `docs/end-to-end-setup-walkthrough.md`

**Changes:**
1. **Tools Section (Line 71–85):** Added `docker buildx` to optional tooling for multi-platform builds
2. **Manual Deployment (Line 457–465):** Added inline note that native builds assume local arch matches cluster, with reference to multi-platform section
3. **New Multi-platform Builds Section (Line 293–335):** 
   - Explains Mac ARM → x86 AKS scenario explicitly
   - Shows `docker info | grep Architecture` to detect local architecture
   - Provides `docker buildx` examples for single-platform (linux/amd64, linux/arm64)
   - Shows multi-platform manifest syntax (linux/amd64,linux/arm64)
   - Warns about registry requirement and --load limitation
4. **Redeploy Section (Line 726–740):** Updated to note native build assumption with commented example of buildx alternative

**Problem Solved:** The original doc used generic `docker build` commands without explaining that users on Mac ARM building for x86 AKS (or vice versa) would produce unusable images.

**Verification:** 
- Checked entire file for lingering x86-only assumptions: none found
- Verified architecture examples (amd64, arm64) appear in context sections
- All 3 service images (expense-api, workflow-engine, notification-svc) have consistent guidance

**Audience Impact:** Platform engineers and operators on Mac ARM (M1/M2/M3 chips) can now:
- Understand why native Docker builds fail in cross-arch scenarios
- Use `docker buildx --platform linux/amd64` for x86 AKS
- Build multi-platform manifests for heterogeneous clusters

### Status: COMPLETE

## Learnings

**Architecture Decisions:**
- RadiusClaim targets Azure/AKS, which commonly runs x86 (amd64) nodes
- Mac ARM developers building locally need explicit buildx guidance
- Multi-platform manifests are the right pattern for teams with mixed architectures

**Patterns:**
- Inline comments work well for architecture assumptions (vs. hiding in separate section)
- Explicit examples (Mac ARM → x86 AKS) help readers recognize their own scenario
- Reference patterns to detailed sub-sections (Multi-platform Builds) keep main flow uncluttered

**File Paths:**
- `docs/end-to-end-setup-walkthrough.md` — the main deployment guide
- Dockerfiles use multi-stage builds; no platform-specific directives needed at the base layer

---

## Phase 9 Completion — Docker Architecture Guidance & GHCR Consistency

**Date:** 2026-03-24  
**Tasks:** Architecture-aware Docker build guidance, GHCR login consistency

### Part 1: Docker Build Architecture Awareness

**File:** `docs/end-to-end-setup-walkthrough.md` (4 sections)

**Problem:** The original walkthrough used generic `docker build` commands without explaining cross-architecture scenarios. Mac ARM developers building for x86 AKS would produce ARM-only images, causing silent pod scheduling failures.

**Solution:** Added comprehensive architecture-aware guidance:
1. Tools section: Added `docker buildx` as optional tooling
2. Manual deployment: Inline note explaining native build assumption, referencing multi-platform section
3. New "Multi-platform Builds" section: Scenario framing, `docker info | grep Architecture`, single and multi-platform buildx examples
4. Redeploy section: Updated with native-build assumption note and buildx alternative

**Verification:** Scanned entire file; no x86-only assumptions remain. Architecture examples consistent across all three services.

**Outcome:** Mac ARM developers can now identify their scenario and use `docker buildx --platform linux/amd64` for x86 AKS deployments. Existing x86→x86 workflows are unaffected.

### Part 2: GHCR Login Variable Consistency

**File:** `docs/end-to-end-setup-walkthrough.md` (lines 436, 583)

**Problem:** Two instances of `docker login ghcr.io` lacked the `--username "$GITHUB_USERNAME"` argument, inconsistent with other docker login commands in the file.

**Solution:** Updated both instances to:
```bash
docker login ghcr.io --username "$GITHUB_USERNAME"
```

**Rationale:** Document already normalizes `GITHUB_USERNAME` in multiple sections. Other login commands (lines 256, 275) already follow this pattern. Consistency improves clarity.

**Outcome:** All GHCR authentication examples now follow the same variable-driven pattern.

### Related Decisions

Decision documents created and merged:
- `eddie-docker-arch-guidance.md`: Full rationale and scope
- `eddie-fix-ghcr-login-var.md`: Variable consistency approach
- User directives (2 captured): Publish script stability, Docker architecture independence

**User Directive (2026-03-24T16:51:40Z):** "When doing `docker build`, keep architecture independence in mind and account for Mac ARM hosts; do not assume x86-only builds or guidance."

This work directly implements that directive.

### Learnings

**Architecture Patterns:**
- RadiusClaim targets Azure/AKS (commonly x86/amd64)
- Mac ARM developers need explicit buildx guidance  
- Multi-platform manifests are the right pattern for mixed-architecture teams
- Inline comments work well for architecture assumptions

**Documentation Principles:**
- Consistency across examples builds user confidence
- Architecture scenarios should be named (e.g., "Mac ARM → x86 AKS") so readers recognize themselves
- Optional advanced patterns should be linked, not embedded in the main flow

**Files:**
- `docs/end-to-end-setup-walkthrough.md` — main deployment guide (lines 71–85, 293–335, 457–465, 726–740)
- Dockerfiles use multi-stage builds; no platform-specific directives needed

### Status: COMPLETE

---

## Phase 10 Work (2026-03-24) — Azure Credential Registration Documentation

### Diagnosed Issue

Graham's recipe troubleshooting identified a critical bootstrap gap:
- Radius Azure recipe deployment fails with missing `azure-azurecloud-default` secret error
- Root cause: Azure credential not registered with Radius before deploying environments with Azure-backed recipes
- The error occurs because `rad credential register azure` must run **after** workspace/environment creation but **before** deploying Bicep files that reference Azure recipes
- This step was missing from both the GitHub Actions workflow and the manual deployment documentation

### Work Completed

**1. README.md Enhancement**
- Added prominent "Azure credential registration (required)" section right after the idempotent deployment paragraph
- Explains the purpose, the exact error message if skipped, and directs readers to validation checklist for details
- Keeps the README narrative high-level while surfacing the criticality

**2. docs/radius-validation-checklist.md — Comprehensive Coverage**
- Added "✅ Azure Provider Credentials" checkbox section in Pre-Deployment Checks
  - Explains what the step does and why it matters
  - Shows the command and expected output
  - References the workflow implementation
  - Separated from workspace/group section for clarity
- Inserted "Step 2: Register Azure Provider Credentials" in Deployment Steps sequence (between environment creation and recipe publishing)
  - Includes the command, verification, and critical warning
  - Maintains step numbering (Steps 3, 4, 5 for recipe publish, environment deploy, app deploy)
- Added new troubleshooting entry: "Issue: `rad deploy` fails with missing `azure-azurecloud-default` secret"
  - Diagnosis, solution with retry, and explanation of why it matters
  - Directs readers to the credential registration step in the pre-deployment section

**3. docs/end-to-end-setup-walkthrough.md — Manual Deployment Path**
- Inserted credential registration block in the "Option B: Manual Deployment with `rad` CLI" section
  - Placed right after `rad env switch` and before `rad deploy` of the environment Bicep
  - Includes interactive prompt explanation and verification command
  - Comments explain what the credential enables (Blob Storage, Service Bus, Key Vault provisioning)

**4. .github/workflows/deploy-azure.yml — CI/CD Implementation**
- Added new step "Register Azure provider credentials with Radius" 
  - Placed between "Configure Radius workspace" and "Deploy Azure-backed Radius environment"
  - Uses the same KUBECONFIG setup as other Radius operations
  - Includes comment explaining the purpose
  - Step runs `./rad credential register azure` with proper environment

### Key Design Decisions

1. **Pre-deployment validation section covers the "what":** Why credentials matter, what happens without them, how to verify success
2. **Deployment steps show the "when":** Exact sequence: create env → register credential → publish recipes → deploy environment → deploy app
3. **Troubleshooting gives the "how to recover":** Diagnosis, retry steps, and explanation of why the error occurred
4. **README surfaces urgency:** The credibility of "this must happen before deployment" is better served by mentioning it in the main narrative than hiding it in a checklist

### Validation

- ✅ All four documentation artifacts (README, walkthrough, validation checklist, workflow) consistently mention credential registration
- ✅ Placed at the right sequence point in all paths
- ✅ Explains the `azure-azurecloud-default` error message (helps operators recognize the issue)
- ✅ Links between docs (validation checklist links to workflow, README links to checklist)
- ✅ No speculative wording; all guidance is grounded in Graham's diagnosis

### Files Modified

1. `README.md` — Added "Azure credential registration (required)" paragraph
2. `docs/radius-validation-checklist.md` — Added pre-deployment check, deployment step, and troubleshooting entry
3. `docs/end-to-end-setup-walkthrough.md` — Added credential registration commands in manual deployment section
4. `.github/workflows/deploy-azure.yml` — Added "Register Azure provider credentials with Radius" job step

### Learnings

- **Bootstrap order matters in Radius:** The sequence is workspace → environment → credential → recipes, not just any order
- **Error messages are documentation:** When an error message mentions a Kubernetes secret name (`azure-azurecloud-default`), that's a hook operators can use to diagnose; calling out the message in the troubleshooting section helps them recognize the failure
- **Credibility in sequence:** Operators trust workflows that show clear step-by-step order more than workflows that hide setup steps
- **CI/CD should mirror manual guidance:** Both paths now have the same credential registration step in the same sequence, reducing mental load for teams moving between automation and manual ops

### Pattern Notes

This aligns with Graham's troubleshooting skill (`radius-azure-recipe-troubleshooting/SKILL.md`):
- Treats Azure provider credentials as a separate bootstrap concern from the environment model
- Separates the "missing credential" symptom from "recipe output contract bugs"
- Points operators to the credential registration step as the first diagnostic/fix

### Status: COMPLETE

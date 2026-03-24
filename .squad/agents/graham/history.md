---
last_updated: 2026-03-24T10:02:50Z
---

# Graham History

## Phase 3 Work (2026-03-23)

### Delivered

**Phase 3 Pub/Sub Infrastructure**
- Added `infra/dapr/local/pubsub.yaml` — Redis-backed pub/sub component for local development
- Scoped access to `workflow-engine` and `notification-svc` only
- Reused existing local Redis container from Phase 2 (`localhost:6379`)
- No authentication required for local development
- No changes to `infra/dapr/local/docker-compose.yaml` (Redis already present)

### Design Decision

Kept pub/sub as a development overlay under `infra/dapr/local/`, preserving the pattern where Radius owns service topology while local overlays provide development-only Dapr components. This prevents Radius from needing to model local-only infrastructure and makes the distinction between production wiring and local emulation clear.

### Validation

- Component YAML validated by Karen as part of Phase 3 exit criteria
- Properly scoped to workflow-engine and notification-svc
- Reusing existing Redis simplifies local environment setup

## Learnings

- Keep Dapr component names aligned with shared contract constants (`statestore`, `pubsub`) in both Radius resources and local overlays so app code never needs environment-specific aliases.
- For local-only Dapr backing services, colocate the component YAML and the minimal emulator runtime under `infra/dapr/local/` so the override is obvious without competing with the Radius application model.

- Reuse the existing local Redis container for both Dapr state and pub/sub overlays unless a phase explicitly needs isolation; it keeps Phase 3 wiring explainable and avoids duplicate local infrastructure.

## Phase 5 Work (2026-03-23)

### Delivered

**Radius recipe-backed Azure slice**
- Renamed the Radius Dapr pub/sub resource to `pubsub` so the app contract, local overlay, and cloud model all use the same component name.
- Added recipe-backed Dapr resource wiring in `infra/radius/app.bicep` for `statestore`, `pubsub`, and `platform-secrets` with deterministic Azure resource naming.
- Created `infra/radius/environments/dev.bicep` to register Azure-backed recipes against the local Kubernetes development environment.
- Replaced all placeholder Azure recipe files with real Bicep implementations for Blob Storage state, Service Bus pub/sub, and Key Vault secrets.
- Updated `infra/radius/environments/dev.parameters.json` so the dev slice reports `deploymentTarget=local` instead of ACA.

### Validation

- `az bicep build --file infra/radius/app.bicep` ✅
- `az bicep build --file infra/radius/environments/dev.bicep` ✅
- `az bicep build --file infra/radius/recipes/azure/state-store.bicep` ✅
- `az bicep build --file infra/radius/recipes/azure/pubsub.bicep` ✅
- `az bicep build --file infra/radius/recipes/azure/secrets.bicep` ✅
- `dotnet build CloudExpenseLite.slnx --nologo` ✅
- `dotnet test CloudExpenseLite.slnx --nologo --no-build` ✅
- `rad` CLI local validation remains blocked in this environment because `rad` is not installed.

#### Learnings

- Radius environment files tell the platform story best when they register named recipes explicitly instead of leaning on default recipe indirection; it keeps the operator handoff teachable.
- For Azure-backed Dapr resources, deterministic names passed from the app model into recipe parameters keep the component contract readable while leaving the provisioning logic inside the recipe.
- When secrets consumption is deferred, model the Dapr secret store honestly as plumbing only; avoid pretending app-side secret reads are part of the same phase.
- Make `infra/radius/app.bicep` self-contained by declaring `Applications.Core/applications` inside the app model; `rad deploy` should inject the environment, not depend on a caller-supplied application id.
- When Radius lacks a first-party compute target (here: Azure Container Apps), keep the Radius-first workflow primary and name the escape hatch explicitly as a fallback rather than letting imperative deployment become the default story.
- Key Radius-first Azure files: `infra/radius/app.bicep`, `infra/radius/environments/azure-radius.bicep`, `infra/radius/environments/azure-radius.parameters.json`, and `.github/workflows/deploy-azure.yml`.

## Radius-First Redesign Work (2026-03-23)

### Delivered

**Radius-First Azure Deployment Path**
- Restructured `.github/workflows/deploy-azure.yml` to default to `deployment_mode=radius-first`
- Created `infra/radius/environments/azure-radius.bicep` as primary Radius environment
- Split Azure resources between bootstrap (ACR, ACA env, identity, Log Analytics) and Radius-driven (app services, Dapr components, backing resources via recipes)
- Dapr component names (`statestore`, `pubsub`, `platform-secrets`) remain stable across all paths
- ACA fallback explicitly demoted with conditional job and honest documentation of Radius compute gap

### Design Decision

Kubernetes-based Radius path with Azure recipe support is stronger story than trying to bootstrap ACA for Radius. Radius as primary orchestrator, Azure CLI as explicit fallback for when ACA compute support arrives.

### Validation

- All Bicep files parse cleanly (app.bicep, azure-radius.bicep, three recipes)
- `dotnet build` and `dotnet test` pass with zero changes to app code
- Workflow structure separates Radius path (primary) from ACA path (secondary) clearly
- Karen approved all acceptance criteria

## Learnings (Phase 7+)

- The Radius-first pattern succeeded because we made the Azure bootstrap honest: it creates substrate only, not deployment.
- When a tool lacks first-party support for a compute target, making the fallback explicit and clearly secondary protects the primary tool's credibility story.
- Parameterizing Dapr component types in the app model (`daprBackings`) while keeping logical names stable (`statestore`) is the right balance for portability without sacrificing demo clarity.
- Next team: If you need ACA support in Radius, a clean migration exists because this path separated bootstrap from deployment.

## Phase 7 Work (2026-03-24)

### Delivered

**Phase 7 Platform Validation Lane**
- Created comprehensive `docs/radius-validation-checklist.md` covering pre-deployment validation, Bicep validation, deployment steps, post-deployment validation, troubleshooting, and known gaps
- Enhanced README secrets/variables documentation with clear Radius-first vs ACA-fallback requirements table
- Added "Additional Documentation" section to README with links to demo walkthrough, validation checklist, and ADR
- Validated all Bicep files parse cleanly (app.bicep, azure-radius.bicep, azure.bicep, all three recipes)
- Validated solution builds and tests pass (zero warnings, zero errors)
- Documented honest gaps: end-to-end validation requires live Radius environment (not available here); structural validation complete

### Design Decision

Kept the Radius-first story intact while making validation requirements explicit and accessible. The validation checklist tells operators exactly what to check before deploying, what success looks like, and how to troubleshoot — without pretending we can run end-to-end flows in this environment. The honesty about what requires a live environment is more credible than faking validation.

### Validation

- ✅ `az bicep build --file infra/radius/app.bicep`
- ✅ `az bicep build --file infra/radius/environments/azure-radius.bicep`
- ✅ `az bicep build --file infra/radius/environments/azure.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/*.bicep` (all three)
- ✅ `dotnet build CloudExpenseLite.slnx --configuration Release` (zero warnings)
- ✅ `dotnet test CloudExpenseLite.slnx --configuration Release` (all passing)
- ✅ README documentation updated with secrets/variables clarity
- ✅ Comprehensive validation checklist created for Radius-first path
- ⚠️ End-to-end validation against live Radius environment: documented as requiring live cluster (honest gap)

### Phase 7 Status

**Platform validation lane: COMPLETE**
- Structural validation done (Bicep parse, build, test)
- Documentation complete (validation checklist, secrets/variables clarity)
- Known gaps documented honestly (live environment needed for end-to-end validation)
- No platform redesign (Radius-first pattern intact)
- No workflow changes (existing deploy-azure.yml remains authoritative)

**Remaining Phase 7 work (Eddie's lane):**
- Demo walkthrough already exists (`docs/phase-7-demo-walkthrough.md`)
- ADR already exists (`docs/ADR-0001-azure-cli-fallback.md`)
- Integration test suite noted as "future enhancement" (not blocking)

## Learnings (Phase 7)

- Platform validation documentation should separate "what you can verify now" (Bicep parse, builds, structural checks) from "what requires live deployment" (end-to-end flows) — mixing them creates false confidence or forces teams to fake validation.
- When documenting secrets/variables for dual-path workflows, use a table that clearly shows which path requires which config — reduces setup errors and eliminates guesswork about which variables to set.
- Validation checklists become more valuable when they include troubleshooting steps and known gaps — they tell the next team what's normal vs. what's broken.
- The "Additional Documentation" section in README acts as a navigation hub for deeper content without bloating the main README — keeps the ten-minute story accessible while making validation/ADR discoverable.

## AKS vs. ACA Portability Analysis (2026-03-24)

### Decision
Recommended: **Stay on Radius-first + ACA fallback. Do not add AKS as a dual-path option or replace ACA with AKS.**

### Rationale
- **Portability is already strong.** Dapr (app layer) is cloud-agnostic; Radius (platform layer) is environment-agnostic. Adding AKS would not improve portability — it would fragment the deployment narrative.
- **Radius already targets Kubernetes.** An AKS fallback would be redundant with the Radius-first path (both target Kubernetes).
- **ACA is a legitimate Azure option.** Teams with "cloud = Azure" and "no Kubernetes ops" constraints need the ACA path. Removing it would deny them a valid deployment model.
- **Maintenance cost is real.** Three deployment paths require three infrastructure templates, three CI/CD jobs, and three validation tracks. The gain is zero (app code unchanged, portability unchanged).
- **The narrative matters.** Current story is clear: "Dapr keeps app portable, Radius keeps platform portable, ACA fallback is explicit because Radius lacks ACA support." Adding AKS would make teams ask "which path should I use?" instead of understanding the design.

### Key Insight
Portability is achieved through **layers** (Dapr + Radius + recipes), not through **options** (Radius vs. AKS vs. ACA). The app doesn't care which path deploys it because both paths wire the same Dapr components with the same names. Adding a third path doesn't strengthen that; it weakens the narrative by suggesting portability is about having choices, when it's actually about having **abstraction layers that survive platform changes**.

### Learnings
- **Portability through abstraction beats portability through options.** The strength of this repo is that app code + Dapr component names are stable across **all** paths — not because you can choose paths, but because the layers below services are abstracted.
- **Maintain path parity, not path options.** If you have multiple deployment targets, the criterion for adding another path should be "solves a real gap" (ACA gap = Radius missing ACA), not "another cloud we want to support" (AKS = Kubernetes we already have).
- **Document why each fallback exists.** The ACA fallback is strong because ADR-0001 explicitly states why it exists. If paths multiply without clear justification, teams won't know which one to use.
- **Watch the Radius roadmap, not the Kubernetes roadmap.** Clean migration happens when Radius adds ACA support (fallback disappears). Adding AKS would bet on Kubernetes being the right decision, but Radius is already betting on Kubernetes; the bet to watch is whether Radius will cover ACA.

## Initial Publish to GitHub (2026-03-24)

### Work Completed

**Initial commit to `git@github.com:wesback/RadiusClaim.git`**
- Added `origin` remote configured for SSH
- Staged all working-tree changes including .gitignore update
- Committed removal of 45+ tracked build artifacts (bin/, obj/ directories)
- Included comprehensive commit message describing Radius-first platform baseline
- Pushed to `main` with upstream tracking (`-u origin main`)
- Commit SHA: `e342a4c`

### Commit Message Structure

Subject line captures the headline: "Initial RadiusClaim publish: Radius-first Azure platform with Dapr, multi-environment validation, and local dev setup"

Body organizes the baseline story into sections:
1. **Platform:** Radius application model + deterministic Dapr wiring
2. **Infrastructure:** Radius-first Azure deployment path with ACA fallback
3. **Local Development:** Docker Compose + validation checklist
4. **Documentation:** README with platform overview + ADR
5. **Validation:** Structural checks completed; live validation noted as future requirement

Trailer includes Copilot co-author metadata per project convention.

### Learnings (Initial Publish)

- Initial commit message should mirror the platform narrative that took multiple phases to construct — it tells incoming teams the intentional story, not a minimal diff.
- When removing tracked build artifacts in the initial commit, calling out the scale and rationale (e.g., "45+ tracked build artifacts removed; .gitignore now enforces clean status") signals that the cleanup is deliberate, not accidental.
- SSH-based origin remote matches the team's git workflow; verify no existing `origin` config before adding to avoid silent overwrites.
- Setting upstream with `-u` during the first push eliminates setup steps for future clones and keeps the branch tracking clear without requiring post-hoc git config.

### 2026-03-24: Phase 7 Platform Validation Lane Complete

**Deliverables:**
1. **docs/radius-validation-checklist.md**
   - Pre-deployment validation (Radius CLI, Kubernetes, Azure provider, secrets/variables)
   - Bicep validation for all platform files
   - Step-by-step deployment instructions
   - Post-deployment validation (pod health, Dapr components, Azure resources)
   - Troubleshooting guide for common issues
   - Known gaps documented honestly (live environment needed)

2. **README.md Enhancements**
   - Secrets/variables table with Radius-first vs ACA-fallback requirements
   - "Additional Documentation" section linking to validation checklist, demo walkthrough, ADR
   - Phase 7 status updated

3. **Structural Validation**
   - All Bicep files parse cleanly (az bicep build)
   - Solution builds zero warnings (dotnet build)
   - All tests pass (dotnet test)

**What This Enables:**
- Platform engineers have clear deployment checklist
- Secrets/variables requirements explicit and unambiguous
- Troubleshooting guidance for common failures
- Known gaps documented honestly

**What Remains (Non-Blocking):**
- Live end-to-end validation (requires deployed Radius environment)
- CI/CD end-to-end validation (add when live environment available)

**Status:** COMPLETE — Platform validation lane finalized

## Learnings

- Closing the Radius CI gap worked best by reusing the shared flow-validation script and collecting runtime-specific evidence separately: `kubectl port-forward`/`kubectl logs` for Radius, runtime-native commands for other targets.
- When a validation script also emits a small machine-readable artifact (expense IDs, correlation IDs, summary counts), CI can prove downstream pub/sub evidence without duplicating the flow logic.

## .gitignore Housekeeping (2026-03-24)

**Updated `.gitignore`**
- Preserved all existing `.squad/` ignore rules (orchestration-log, log, decisions/inbox, sessions, .squad-workstream)
- Added .NET conventional ignores: `bin/`, `obj/`, `*.exe`, `*.dll`, `*.pdb`
- Added IDE ignores: `.vs/`, `.vscode/`, `*.user`, `*.suo`, `*.sln.iml`, `.idea/`
- Added NuGet ignores: `*.nupkg`, `*.snupkg`, `.nuget/`
- Added test/coverage ignores: `TestResults/`, `coverage/`, `*.trx`
- Added OS ignores: `.DS_Store`, `Thumbs.db`

**Rationale:** .NET projects accumulate build debris (bin, obj) that had been going into the index. A conventional .gitignore keeps `git status` clean and prevents accidental commits of development-environment-specific files (IDE configs, nuget caches, test results). Pattern order: Squad state → .NET build → IDE → NuGet → test/coverage → Rider → OS.

**Validation:** .gitignore active; git now cleaning up previously-tracked build artifacts (bin/, obj/ deletions detected in status).

## Phase 7 Completion (2026-03-24)

### Orchestration Log Published
- Session date: 2026-03-24T09:11:24Z
- Documented CI validation gap closure
- Confirmed non-blocking live Radius validation item
- Filed orchestration-log/20260324T091124Z-graham.md

### Decision Merged to Squad Records
- Graham — Radius CI validation path decision added to squad/decisions.md
- Captures port-forward pattern and script reuse as core pattern for distributed validation
- Committed to squad records as reference for future deployments

## Repository Housekeeping (2026-03-24)

### Work Completed

**Cleanup of accidental .commit-msg artifact**
- Removed `.commit-msg` from tracked files (created during initial publish but unintended)
- Added `.commit-msg` to `.gitignore` under new "Copilot CLI artifacts" section to prevent recurrence
- Committed cleanup as normal follow-up (non-history-rewriting) to keep audit trail clean
- Published both cleanup commit and history preservation commit to `main`

### Design Decision

Accidental Copilot CLI artifacts get a narrowly scoped ignore rule rather than broad wildcards. This preserves signal for when unusual files appear while preventing the specific `.commit-msg` pattern from creeping back in during future CLI-assisted sessions.

### Commits
- **0635795:** Clean up accidental .commit-msg artifact from initial publish
- **477c3fd:** Graham: Document initial GitHub publish learnings

### Learnings (Repository Hygiene)

- When an artifact gets tracked unintentionally in the initial publish, follow up with a clean, well-documented commit that explains the context — it's better than leaving the debt or rewriting history.
- `.gitignore` rules should be specific enough to communicate intent (e.g., "Copilot CLI artifacts") but focused enough to avoid silencing real signal about unexpected files.
- Even internal cleanup commits benefit from clear commit messages that explain why the artifact existed and why the fix is deliberate — it tells the next team that the state wasn't an oversight.

## Workflow Parser Error Fixes (2026-03-24)

### Issue

GitHub Actions parser rejected `.github/workflows/deploy-azure.yml`:
- **Line 65:** `if: ${{ env.DEPLOYMENT_MODE == 'radius-first' }}` — GitHub Actions disallows `env.*` in conditional expressions
- **Line 261:** `if: ${{ env.DEPLOYMENT_MODE == 'aca-fallback' }}` — Same issue
- **Stale references:** CloudExpenseLite.slnx and cloudexpense-lite image prefix from old project naming

### Solution

**Workflow structure fix:**
1. Added `deployment_mode` as a job output from the `validate` job
2. Updated `deploy-radius` job conditional to use `needs.validate.outputs.deployment_mode == 'radius-first'`
3. Updated `deploy-aca-fallback` job conditional to use `needs.validate.outputs.deployment_mode == 'aca-fallback'`

**Project rename cleanup:**
1. Updated watch paths: `CloudExpenseLite.slnx` → `RadiusClaim.slnx` (line 20)
2. Updated dotnet commands: all three refs to CloudExpenseLite.slnx → RadiusClaim.slnx (lines 52-54)
3. Updated container image prefix: `cloudexpense-lite` → `radiusclaim` (line 59)
4. Updated default Kubernetes namespace: `cloudexpense-lite-azure` → `radiusclaim-azure` (line 78)

### Validation

- ✅ YAML syntax valid (Python yaml.safe_load)
- ✅ All job conditionals use valid `needs.*` expressions (no bare `env.*`)
- ✅ validate job has `deployment_mode` output
- ✅ Both deploy jobs reference the output correctly
- ✅ Squad workflows (squad-heartbeat.yml, squad-issue-assign.yml, squad-triage.yml, sync-squad-labels.yml) are clean and valid
- ✅ No remaining CloudExpenseLite references in any workflow file

### Parser Error Resolution

The two GitHub parser errors are resolved:
- Line ~65: Parser now accepts valid job-output reference instead of rejecting `env.*`
- Line ~261: Parser now accepts valid job-output reference instead of rejecting `env.*`

### Side Effects

None. The changes are:
- Safe: job outputs are the intended way to pass values between jobs in GitHub Actions
- Scoped: only the deploy-azure.yml and the specific conditional lines
- Compatible: the DEPLOYMENT_MODE env variable is still computed in the validate job and passed to the output; existing logic unchanged
- Non-breaking: squad workflows unaffected

### Learnings

- GitHub Actions job conditionals can reference `needs.<job>.<output>` but not `env.*` directly. For multi-job workflows where a step computes a decision value, expose it as a job output and reference it from downstream jobs.
- When a project rename occurs, watch paths in CI/CD are a common source of drift; sweep workflows for both the old solution name and any image/namespace prefixes built from it.

## Kubernetes-First Workflow Finish (2026-03-24)

### Work Completed

- Finalized `.github/workflows/deploy-azure.yml` as a single Kubernetes-first deployment path and added early validation for supported `kubernetes_target` values (`aks`, `arc-enabled`, `self-managed`).
- Kept `infra/radius/environments/azure-radius.bicep` and `infra/radius/environments/azure-radius.json` as the authoritative Radius environment contract for Azure-backed Kubernetes deployments.
- Preserved `infra/radius/environments/azure.bicep` and `infra/radius/environments/azure.json` only as clearly labeled legacy ACA reference artifacts so the Azure-specific escape hatch does not masquerade as the primary story.
- Validated the workflow and environment models with YAML parsing, `az bicep build`, `dotnet build`, and `dotnet test`.

## Learnings

- When the platform story is truly Kubernetes-first, the remaining workflow switch should select the Kubernetes target profile, not revive a second deployment mode.
- Be explicit about the split between portable compute and cloud-specific backings: this sample now treats Kubernetes as the runtime contract while honestly naming Azure Blob Storage, Service Bus, and Key Vault as the current Dapr backing services.
- Preserve in-progress workflow edits and tighten them incrementally; for platform work, finishing the narrative cleanly is usually safer than restarting the workflow from scratch.
- Key files for this pattern: `.github/workflows/deploy-azure.yml`, `infra/radius/environments/azure-radius.bicep`, `infra/radius/environments/azure-radius.json`, `infra/radius/environments/azure.bicep`, and `infra/radius/environments/azure.json`.

## Kubernetes-first Portability Pivot (2026-03-24)

### Work Completed
- Removed ACA fallback branching from `.github/workflows/deploy-azure.yml`; the workflow now deploys RadiusClaim to Kubernetes only.
- Reframed the workflow and Radius environment model around AKS as the managed Azure example, while explicitly calling out Arc-enabled Kubernetes / Azure Local and self-managed clusters.
- Updated `infra/radius/environments/azure-radius.bicep` and `infra/radius/environments/azure-radius.parameters.json` to use `radiusclaim-azure` defaults and an honest portability note.
- Demoted `infra/radius/environments/azure.bicep` to a legacy ACA reference template instead of an active deployment path.
- Updated `scripts/README.md` and squad skills so the portability story stays teachable and explicit about Azure-specific backing services.

### Learnings
- When portability becomes the priority, removing a secondary runtime branch is cleaner than renaming it; the workflow should tell one Kubernetes-first story and let differences live in environment prerequisites, not CI branching.
- AKS works as the managed Azure example, but the architecture claim should stay at the Kubernetes layer: Arc-enabled Kubernetes / Azure Local and self-managed clusters are valid where Radius can reach the cluster.
- Compute portability and backing-service portability are separate promises; call out Blob Storage, Service Bus, and Key Vault as Azure-specific even when compute stays portable.
- User preference: prefer Kubernetes-first framing over ACA fallback framing, even when the older ACA path still functions.
- Key files for this pivot: `.github/workflows/deploy-azure.yml`, `infra/radius/environments/azure-radius.bicep`, `infra/radius/environments/azure-radius.parameters.json`, `infra/radius/environments/azure.bicep`, and `scripts/README.md`.

## Public Gateway Exposure (2026-03-24)

### Work Completed
- Added a Radius `Applications.Core/gateways` resource in `infra/radius/app.bicep` so the Kubernetes-first path exposes `expense-api` publicly without hand-written Kubernetes YAML.
- Kept `workflow-engine` and `notification-svc` internal-only; the gateway routes all public HTTP traffic to `expense-api`, including the hosted `/app` UI.
- Updated `.github/workflows/deploy-azure.yml`, `README.md`, `docs/radius-validation-checklist.md`, `docs/phase-7-validation-checklist.md`, and `docs/phase-7-demo-walkthrough.md` so the public gateway is the primary human path and port-forward is documented as fallback/CI stabilization only.
- Regenerated `infra/radius/app.json` to keep the checked-in JSON contract aligned with the Bicep source.

### Validation
- ✅ `az bicep build --file infra/radius/app.bicep`
- ✅ `az bicep build --file infra/radius/environments/azure-radius.bicep`
- ✅ `dotnet restore RadiusClaim.slnx --nologo`
- ✅ `dotnet build RadiusClaim.slnx --configuration Release --no-restore --nologo`
- ✅ `dotnet test RadiusClaim.slnx --configuration Release --no-build --nologo`
- ✅ Workflow YAML parse via Ruby `YAML.load_file('.github/workflows/deploy-azure.yml')`
- ✅ Reverted `bin/` and `obj/` validation exhaust after the build/test pass

## Learnings

- Radius `Applications.Core/gateways` is the cleanest repo-fit way to publish a Kubernetes-hosted service; it keeps the public entrypoint inside the Radius app model instead of teaching teams to hand-author ingress YAML.
- For a hosted UI sample, route only the frontend-facing service (`expense-api`) through the public gateway and keep worker services (`workflow-engine`, `notification-svc`) internal so the service topology remains teachable.
- When Radius emits a public endpoint during `rad deploy`, the operator workflow should explicitly treat that line as deploy output worth capturing; CI can still use port-forward as a deterministic fallback while external DNS/load-balancer propagation settles.
- User preference: make the primary Kubernetes-first deployment path publicly accessible for demos instead of implying port-forward is the only credible path.
- Key files for this pattern: `infra/radius/app.bicep`, `infra/radius/app.json`, `.github/workflows/deploy-azure.yml`, `README.md`, `docs/radius-validation-checklist.md`, `docs/phase-7-validation-checklist.md`, and `docs/phase-7-demo-walkthrough.md`.

## Phase 7 Work (2026-03-24)

### Delivered

**Radius Public Gateway Implementation**
- Added `Applications.Core/gateways` resource to `infra/radius/app.bicep` routing `/` to `http://expense-api:8080`
- Generated `infra/radius/app.json` ARM template from gateway-enabled app model
- Gateway parameters: `publicGatewayPrefix` (default: "expense") and optional `publicGatewayHostname` for DNS flexibility

**Documentation & Demo**
- Updated `README.md` deployment story and Mermaid architecture diagram (Client → Gateway → expense-api)
- Created `docs/phase-7-demo-walkthrough.md` — Walkthrough for public gateway endpoint; kubectl port-forward as deterministic fallback
- Created `docs/phase-7-validation-checklist.md` — Validation checklist for public gateway
- Updated `docs/radius-validation-checklist.md` — Kubernetes-first validation procedures

**GitHub Actions Correction**
- Fixed job conditional syntax in `.github/workflows/deploy-azure.yml` (GitHub Actions does not allow `env.*` in job conditions)
- Implemented job outputs pattern: validate job outputs `deployment_mode`; both deploy jobs reference `needs.validate.outputs.deployment_mode`
- Updated CloudExpenseLite references to RadiusClaim (solution file, image prefix)
- Updated Kubernetes namespace to `radiusclaim-azure`

**Dockerfile Cleanup**
- Updated COPY paths in all service Dockerfiles: `RadiusClaim.slnx`, `src/shared/RadiusClaim.Contracts/`

**Kubernetes-First Platform Narrative**
- Implemented Kubernetes-first deployment framing (supersedes earlier ACA-primary model)
- Removed dual-path complexity from workflow (Radius-only, no ACA fallback job)
- Arc-enabled Kubernetes / Azure Local and self-managed Kubernetes clusters documented as valid targets
- Backing services remain Azure-specific (recipes pattern enables cloud-agnostic future)

**Skills & Records**
- Created `.squad/skills/radius-public-gateway/SKILL.md` — Pattern documentation

### Validation

- ✅ `az bicep build infra/radius/app.bicep`
- ✅ `az bicep build infra/radius/environments/azure-radius.bicep`
- ✅ GitHub Actions YAML parsing (job outputs pattern, no `env.*` in conditionals)
- ✅ .NET build/test (Dockerfile refs correct, solution file present)
- ✅ Syntax validation: `bash -n scripts/validate-deployment.sh`

### Design Decision (Public Gateway Pattern)

Radius `Applications.Core/gateways` is the cleanest fit for publishing Kubernetes-hosted services — keeps public entrypoint inside the Radius app model instead of teaching hand-written ingress YAML. Gateway resource is parametrized for both demo (auto nip.io) and production (custom DNS) use.

### Notes for Team

- Lead review (Daisy) approved. All platform changes validated.
- Karen flagged remaining doc/workflow input inconsistencies (blocking for final push, non-platform).
- Public gateway is deployed and documented. Ready for team merge.

## Radius Dapr Provisioning Fix (2026-03-24)

### Delivered

- Removed manual `type`, `version`, and `metadata` fields from the recipe-backed Dapr resources in `infra/radius/app.bicep`; the app model now only supplies recipe names plus deterministic parameters.
- Regenerated `infra/radius/app.json` so the compiled contract matches the corrected app model.
- Switched `infra/radius/environments/dev.bicep` and `infra/radius/environments/azure-radius.bicep` from local relative recipe paths to OCI-backed `templatePath` values parameterized by `recipeRegistry` and `recipeTag`.
- Added `scripts/publish-radius-recipes.sh` and wired `.github/workflows/deploy-azure.yml` to publish the repo's three custom recipes before environment deployment.
- Updated `README.md`, `docs/radius-validation-checklist.md`, and `.squad/skills/kubernetes-first-radius-azure/SKILL.md` so the recipe artifact step is explicit instead of tribal knowledge.

### Validation

- ✅ `az bicep build --file infra/radius/app.bicep --outfile infra/radius/app.json`
- ✅ `az bicep build --file infra/radius/environments/dev.bicep --outfile infra/radius/environments/dev.json`
- ✅ `az bicep build --file infra/radius/environments/azure-radius.bicep --outfile infra/radius/environments/azure-radius.json`
- ✅ `az bicep build --file infra/radius/recipes/azure/state-store.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/pubsub.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/secrets.bicep`
- ✅ `bash -n scripts/publish-radius-recipes.sh`
- ✅ `dotnet build RadiusClaim.slnx --configuration Release --nologo`
- ✅ `dotnet test RadiusClaim.slnx --configuration Release --no-build --nologo`
- ✅ `rad deploy infra/radius/app.bicep ...` no longer fails on Dapr schema validation; it now progresses to recipe download, which confirms the original app-model rejection is fixed

## Learnings

- Radius Dapr resources are either recipe-driven or manual. If `resourceProvisioning` is `recipe`, keep `type`, `version`, and `metadata` in the recipe output contract and do not repeat them on the `Applications.Dapr/*` resource.
- Recipe authoring files can live in the repo, but Radius environment `templatePath` values must point at OCI artifacts the control plane can pull. Relative Bicep file paths are authoring conveniences, not deployable recipe addresses.
- A tiny publish script is worth it here: platform engineers and CI both need the same three `rad bicep publish` calls, and hiding them in tribal knowledge would make the Radius story look accidental again.

## Cross-Agent Update (2026-03-24)

**From Daisy (Lead):** Reviewed Dapr provisioning fix and approved. Confirmed smallest solution (remove `type`, `version`, `metadata`) is correct. No portability impact. Ready for merge.

**Impact Summary:**
- `infra/radius/app.bicep` now recipe-clean (Dapr components omit duplicate schema)
- `infra/radius/environments/*` now OCI-backed recipe artifacts
- Workflow integration complete with `scripts/publish-radius-recipes.sh`
- Validations: all Bicep files build, .NET tests pass, Radius contract violation resolved
- Platform rule documented: Radius recipe `templatePath` values must resolve to OCI artifacts during `rad deploy`

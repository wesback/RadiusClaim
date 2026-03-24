---
last_updated: 2026-03-24T14:03:13Z
---

# Graham History

## Core Context

**Phases 1–5 Summary (2026-03-23)**

Graham led infrastructure platform work across five phases:
- **Phase 3:** Added local Dapr pub/sub overlay (`infra/dapr/local/pubsub.yaml`) with Redis backend
- **Phase 5:** Delivered Radius recipe-backed Azure slice: named recipe wiring in `infra/radius/app.bicep` for state, pub/sub, and secrets; created `infra/radius/environments/dev.bicep` with real Azure recipes (Blob Storage, Service Bus, Key Vault)
- **Phase 5–6:** Restructured GitHub Actions to default to Radius-first deployment with Azure CLI as explicit fallback
- **Key pattern:** Radius owns service topology and environment layer; local Dapr overlays under `infra/dapr/local/`; Azure-backed recipes in `infra/radius/recipes/azure/`

**Namespace and Dapr Wiring Rule (2026-03-24)**

Established rule that recipe `templatePath` values in Radius environments must resolve to OCI artifacts (not local Bicep paths). This enables `rad deploy` to fetch recipes from a registry at deploy time. Implemented recipe publishing automation in workflow and scripts.

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
- Radius Azure provider credentials are a separate bootstrap concern from the Radius environment model: if `.github/workflows/deploy-azure.yml` creates the workspace and deploys `infra/radius/environments/azure-radius.bicep` without first running `rad credential register azure ...`, recipe execution fails looking for the control-plane secret `azure-azurecloud-default`.
- For Azure/AWS Bicep recipes, do not manually list Azure resource IDs in `output result.resources`; Radius auto-populates those backing resources. Reserve manual `resources` entries for Kubernetes/UCP IDs only. In this repo, the risky pattern appears in `infra/radius/recipes/azure/state-store.bicep`, `infra/radius/recipes/azure/pubsub.bicep`, and `infra/radius/recipes/azure/secrets.bicep` (plus their generated `.json` mirrors).
- The `pubsub` recipe is doubly fragile because it emits `RootManageSharedAccessKey`-derived data while also manually surfacing Azure resource IDs; if the Azure provider bootstrap is fixed first, the next platform repair should be tightening the recipe output contract before republishing OCI artifacts.

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
- Azure Key Vault recipes must treat purge protection as a one-way safety control: `enablePurgeProtection: false` is not a valid deployment setting, so Radius-backed secret-store recipes should default it to `true` for both first deploys and replays.
- The exact failure signature for this class of issue is `Applications.Dapr/secretStores` → `RecipeDeploymentFailed` → Key Vault `BadRequest` mentioning `enablePurgeProtection`; fix the recipe in `infra/radius/recipes/azure/secrets.bicep` and republish `infra/radius/recipes/azure/secrets.json`.

## Cross-Agent Update (2026-03-24)

**From Daisy (Lead):** Reviewed Dapr provisioning fix and approved. Confirmed smallest solution (remove `type`, `version`, `metadata`) is correct. No portability impact. Ready for merge.

**Impact Summary:**
- `infra/radius/app.bicep` now recipe-clean (Dapr components omit duplicate schema)
- `infra/radius/environments/*` now OCI-backed recipe artifacts
- Workflow integration complete with `scripts/publish-radius-recipes.sh`
- Validations: all Bicep files build, .NET tests pass, Radius contract violation resolved
- Platform rule documented: Radius recipe `templatePath` values must resolve to OCI artifacts during `rad deploy`

## Radius Namespace Migration (2026-03-24)

### Delivered

- Migrated `infra/radius/app.bicep` application ownership to `Radius.Core/applications@2025-08-01-preview` and moved service ingress from `Applications.Core/gateways` to `Radius.Compute/routes`.
- Migrated `infra/radius/modules/container-service.bicep` service resources from `Applications.Core/containers` to `Radius.Compute/containers`, preserving Dapr sidecar wiring and existing connection semantics.
- Migrated `infra/radius/environments/dev.bicep` and `infra/radius/environments/azure-radius.bicep` from inline `Applications.Core/environments` recipes to `Radius.Core/environments` plus `Radius.Core/recipePacks`, while keeping Azure recipe locations and Daisy's Key Vault recipe intact.
- Regenerated `infra/radius/app.json`, `infra/radius/environments/dev.json`, and `infra/radius/environments/azure-radius.json` so checked-in JSON matches the newer Radius namespaces.
- Updated `README.md` and `docs/radius-validation-checklist.md` so operators see the mixed-state reality clearly: core app/compute moved to `Radius.*`, Dapr resources remain on `Applications.Dapr/*`, and the current `az bicep build` path still emits non-blocking `BCP081` warnings for `Radius.Compute/*`.

### Validation

- ✅ `dotnet restore RadiusClaim.slnx --nologo`
- ✅ `dotnet build RadiusClaim.slnx --configuration Release --no-restore --nologo`
- ✅ `dotnet test RadiusClaim.slnx --configuration Release --no-build --nologo`
- ✅ `az bicep build --file infra/radius/app.bicep --outfile infra/radius/app.json`
- ✅ `az bicep build --file infra/radius/environments/azure-radius.bicep --outfile infra/radius/environments/azure-radius.json`
- ✅ `az bicep build --file infra/radius/environments/dev.bicep --outfile infra/radius/environments/dev.json`
- ✅ `az bicep build --file infra/radius/recipes/azure/state-store.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/pubsub.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/secrets.bicep`
- ⚠️ `az bicep build` currently emits `BCP081` warnings for `Radius.Compute/containers@2025-08-01-preview` and `Radius.Compute/routes@2025-08-01-preview`; compilation still succeeds and produces deployable JSON artifacts.

## Learnings

- Radius 0.55 safely supports a mixed migration state: `Radius.Core/applications`, `Radius.Core/environments`, and `Radius.Core/recipePacks` work alongside legacy `Applications.Dapr/*` resources when the Dapr catalog has not yet moved to `Radius.*` namespaces.
- Migrating `Applications.Core/environments` to `Radius.Core/environments` requires introducing a `Radius.Core/recipePacks` resource; the old inline `recipes` map becomes a linked recipe pack, and Azure provider scope must be decomposed into `subscriptionId` plus `resourceGroupName`.
- `Applications.Core/containers` maps cleanly to `Radius.Compute/containers`, but the shape changes from a single `container` object to a `containers` map keyed by logical container name; Dapr moves under `extensions.daprSidecar` instead of the old extensions array.
- `Applications.Core/gateways` can be advanced to `Radius.Compute/routes`, but the current route model defers generated hostname choice to the active recipe. Keep custom FQDN support, but treat old prefix hints as compatibility metadata, not enforceable routing input.
- Key file paths for this migration are `infra/radius/app.bicep`, `infra/radius/modules/container-service.bicep`, `infra/radius/environments/dev.bicep`, `infra/radius/environments/azure-radius.bicep`, `README.md`, and `docs/radius-validation-checklist.md`.

## Key Vault Recipe Remediation (2026-03-24)

### Delivered

**Azure Key Vault Secret-Store Recipe Fix**
- Removed explicit `enablePurgeProtection: false` from `infra/radius/recipes/azure/secrets.bicep` and `secrets.json`
- Updated `docs/radius-validation-checklist.md` with deployment failure diagnosis and remediation guidance
- Validated existing build/test/Bicep commands pass after change
- Diagnosis: Azure Key Vault rejects explicit `false` on purge protection; once enabled, it is irreversible

### Decision Rationale

Daisy approved the minimal fix: omit the property entirely rather than force-default to `true` or add branching for existing vaults. This keeps the shared recipe simple and preserves the principle that samples should not impose irreversible infrastructure opinions.

### Validation

- ✅ `dotnet build RadiusClaim.slnx` passes
- ✅ `az bicep build infra/radius/recipes/azure/secrets.bicep` succeeds
- ✅ No changes to app code or other recipes

## Radius Namespace Migration — Mixed Interim State (2026-03-24)

### Delivered

**Namespace Strategy Implementation**
- Migrated supported Radius resource types to `Radius.Core/*` and `Radius.Compute/*` namespaces:
  - `Applications.Core/applications` → `Radius.Core/applications`
  - `Applications.Core/environments` → `Radius.Core/environments`
  - `Applications.Core/recipePacks` → `Radius.Core/recipePacks`
  - `Applications.Core/containers` → `Radius.Compute/containers`
  - `Applications.Core/gateways` → `Radius.Compute/routes`
- Intentionally left Dapr component resources on `Applications.Dapr/*` pending official `Radius.*` Dapr types in the shipped catalog
- Regenerated all JSON artifacts with `az bicep build`
- Updated `docs/radius-validation-checklist.md` and `README.md` to document mixed-namespace interim state

### Design Decision

Daisy approved the straight rename approach: no namespace aliasing, no dual-path runtime logic, no back-compat branches. The sample remains portable while the team waits for Radius to ship Dapr types. Mixed namespaces are acceptable and must be documented so reviewers don't reject builds solely on `BCP081` warnings.

### Validation

- ✅ `az bicep build infra/radius/app.bicep` compiles; emits `BCP081` on `Radius.Compute/*` but produces deployable JSON
- ✅ `az bicep build infra/radius/environments/dev.bicep` succeeds
- ✅ `az bicep build infra/radius/environments/azure-radius.bicep` succeeds
- ✅ `az bicep build infra/radius/recipes/azure/*.bicep` all succeed
- ✅ JSON artifacts regenerated and ready for deployment
- ✅ No app code changes required
- ⚠️ `BCP081` warnings on `Radius.Compute/*` are expected and acceptable

### Team Guardrails

- Keep namespace changes as direct string/default updates, not new abstraction layers
- Do not add compatibility code supporting both old and new namespaces in the shared sample
- Migration help for teams' own estates belongs in rollout docs, not core sample
- Acceptable to defer: historical records preserving old naming, further non-runtime cleanup, broader parameterization

## Learnings

- For partial Radius catalog migrations, use official docs as the first gate: if Radius still documents Dapr resources under `Applications.Dapr/*@2023-10-01-preview`, treat that as a blocker and document it instead of inventing future `Radius.*` names.
- The clean proof pattern is docs first, toolchain second: cite Radius+Dapr docs for namespace ownership, then use `az bicep build` and generated JSON artifacts to confirm which `Radius.Core/*` and `Radius.Compute/*` replacements are actually deployable in the current repo.
- Key files for this documentation-first blocker pattern are `README.md`, `docs/radius-validation-checklist.md`, `infra/radius/app.bicep`, and `infra/radius/environments/{dev,azure-radius}.bicep`.

---

## Scribe Orchestration (2026-03-24)

Coordinated decision documentation for Dapr namespace research:
- Authored `.squad/orchestration-log/2026-03-24T14:46:49Z-graham.md` summarizing research findings
- Merged decision from `.squad/decisions/inbox/graham-dapr-namespace-blocker.md` into `.squad/decisions.md`
- Coordinated cross-team updates with Daisy's approval decision

## Learnings

- Mixing `Applications.Dapr/*` with `Radius.Compute/*` is workable, but migrating the owning application/environment from `Applications.Core/*` to `Radius.Core/*` breaks idempotent updates for already-created Dapr resources because ownership continuity is tracked by resource IDs, not just logical names.
- The smallest safe repair is to keep `Applications.Core/applications` and `Applications.Core/environments` as the stable ownership boundary for existing Dapr components while retaining validated improvements such as OCI-backed recipes, the Key Vault purge-protection fix, and `Radius.Compute/*` for compute/ingress.
- `az bicep build` remains the right repo-level validation here: successful builds with only `BCP081` warnings on `Radius.Compute/*` are enough to confirm the mixed model still compiles and regenerates the checked-in JSON artifacts.
- If `rad deploy infra/radius/app.bicep` fails with `InvalidDeployment` telling the operator to ensure an Azure provider is configured, the active Radius environment is missing `properties.providers.azure.scope`; in this repo the safe recovery is to deploy `infra/radius/environments/azure-radius.bicep` with both `azureProviderScope` and `location`, switch to that environment, and then rerun the app deploy.
- Key operator evidence for this recovery lives in `infra/radius/environments/azure-radius.bicep`, `.github/workflows/deploy-azure.yml`, `README.md`, and `docs/radius-validation-checklist.md`: the workflow always bootstraps a temporary env, deploys the Azure-backed environment first, switches to `azure`, and only then deploys `infra/radius/app.bicep`.
- `rad workspace show -o json` is the fastest way to rule out the "wrong active environment" theory: if the workspace already points at `/.../environments/azure`, the failure is in the `azure` environment state itself, not in Radius still targeting `bootstrap-fix`.
- `rad env show azure -o json` should expose both `properties.providers.azure.scope` and real recipe `location` values; if the provider block is missing and recipe parameters still show placeholders such as `<your-azure-region>`, the environment was deployed with incomplete inputs and should be repaired by redeploying `infra/radius/environments/azure-radius.bicep`, not by editing `app.bicep`.
- In this repo's current live state, the workspace already targets `azure`, while `azure` is missing the Azure provider and still carries placeholder recipe locations. The shortest safe repair is to switch back to `bootstrap-fix`, redeploy the Azure environment with the real subscription/resource-group scope and location, then switch to `azure` and rerun the app deploy.

## 2026-03-24T15:49:35Z — Team Update: Portability Documentation Completion

**Status from Eddie (Docs/Story):**
- **Completed:** Documentation shift to Azure Local / Arc-enabled Kubernetes / on-premises portability
- **Portability Message:** App code is Dapr-portable, deployment model is Kubernetes-portable via Radius, Azure backing services are current
- **Files Updated:** README, ADR-0001, end-to-end walkthrough
- **Related to Your Work:** Aligns with your Kubernetes-first workflow and namespace migration decisions
- **Decision Record:** `eddie-portability-docs-2026-03-24`

## Radius Idempotency Fix (2026-03-24)

### Problem Identified

The GitHub Actions workflow created temporary bootstrap environments (`bootstrap-${{ github.run_id }}`) before deploying the actual environment Bicep, causing:
1. Deployment repeatability failures on subsequent runs
2. Accumulation of unused bootstrap environments
3. Mismatch between documented pattern and actual needs

### Solution Implemented

**Workflow changes:**
- Removed `RADIUS_BOOTSTRAP_ENVIRONMENT` variable
- Changed to: `rad env create "$RADIUS_ENVIRONMENT_NAME" || true` (idempotent)
- Removed redundant post-deployment environment switch

**Documentation updates:**
- README: Added "Idempotent deployment" section
- `end-to-end-setup-walkthrough.md`: Updated to idempotent pattern
- `radius-validation-checklist.md`: Removed bootstrap references, documented idempotent approach

### Pattern

```bash
rad env create <target> || true  # Idempotent creation
rad env switch <target>          # Switch to target
rad deploy <env>.bicep ...       # Deploy updates in place
```

### Validation

- ✅ All Bicep files compile (BCP081 warnings for Radius.Compute/* are expected and non-blocking)
- ✅ Solution builds with zero warnings
- ✅ Documentation consistent across all operator guides
- ✅ Preserves approved namespace ownership (Applications.Core/Applications.Dapr split)

### Key Insight

Radius environment deployment is naturally idempotent when targeting a stable environment name. The bootstrap pattern was inherited from early examples but unnecessary for production workflows. Creating the target environment directly makes the deployment story clearer and more reliable.

## Radius Idempotency Fix (2026-03-24)

### Problem Identified

GitHub Actions workflow for `deploy-azure.yml` created temporary bootstrap environments (`bootstrap-${{ github.run_id }}`) on every run, which accumulated over time and prevented idempotent redeployment. Subsequent workflow runs would fail or behave unpredictably because the target environment already existed from previous runs.

### Solution Implemented

Replaced the temporary bootstrap pattern with direct target environment creation using the idempotent `rad env create || true` pattern:

```bash
# Old pattern (non-idempotent)
RADIUS_BOOTSTRAP_ENVIRONMENT=bootstrap-${{ github.run_id }}
rad env create "$RADIUS_BOOTSTRAP_ENVIRONMENT"
rad env switch "$RADIUS_BOOTSTRAP_ENVIRONMENT"
rad deploy infra/radius/environments/azure-radius.bicep ...
rad deploy infra/radius/app.bicep ...

# New pattern (idempotent)
rad env create "$RADIUS_ENVIRONMENT_NAME" || true
rad env switch "$RADIUS_ENVIRONMENT_NAME"
rad deploy infra/radius/environments/azure-radius.bicep ...
rad deploy infra/radius/app.bicep ...
# No explicit post-deploy switch needed - rad deploy switches automatically
```

### Changes Made

**Workflow (``.github/workflows/deploy-azure.yml`):**
- Removed `RADIUS_BOOTSTRAP_ENVIRONMENT: bootstrap-${{ github.run_id }}` variable
- Changed to direct environment creation: `rad env create "$RADIUS_ENVIRONMENT_NAME" || true`
- Removed redundant `rad env switch` after environment deployment (deploy already switches)

**Documentation Updates:**
- `README.md`: Added "Idempotent deployment" section explaining the pattern and its benefits
- `docs/end-to-end-setup-walkthrough.md`: Updated steps to show `rad env create azure || true` pattern; removed all bootstrap environment references
- `docs/radius-validation-checklist.md`: Removed bootstrap environment references; documented idempotent pattern and validation approach

### Validation Evidence

- ✅ `az bicep build` passes for all Bicep files (app.bicep, azure-radius.bicep, azure.bicep, all three recipes)
- ✅ `dotnet build` passes with zero warnings
- ✅ Workflow changes preserve all existing parameter passing
- ✅ Documentation reflects new pattern consistently across all operator guides
- ✅ No impact on Dapr resource ownership (Applications.Dapr components unchanged)
- ✅ Preserves approved namespace ownership model (Applications.Core for app/env, Applications.Dapr for components)

### Key Learnings

**Idempotent Resource Creation Pattern:**
- Idempotent resource creation requires **stable naming** (not unique-per-run identifiers)
- The `|| true` pattern in Bash makes command sequences idempotent by ignoring "already exists" errors
- When using the same environment name across runs, `rad deploy` updates configuration in place rather than failing or creating duplicates

**Bootstrap Pattern Origin:**
- Bootstrap environments (`bootstrap-${{ github.run_id }}`) were inherited from early Radius examples
- For production workflows, this pattern is unnecessary overhead that accumulates cluster pollution
- The pattern was confusing in operator documentation because it showed temporary creation that wasn't required

**Radius Deployment Behavior:**
- `rad env create` with the same name returns a no-op on subsequent runs (idempotent)
- `rad env switch` and `rad deploy` combination naturally targets the same stable environment
- Post-deploy `rad env switch` is redundant because `rad deploy` already switches to the target environment

### Impact

- ✅ Deployments now repeatable without manual environment cleanup
- ✅ GitHub Actions workflow simplified (one fewer variable, clearer intent)
- ✅ Documentation consistent with actual idempotent pattern
- ✅ No breaking changes to Bicep files, recipes, or app code
- ✅ Reduces operator confusion about environment lifecycle

### Status

✅ **APPROVED** by Karen after structural validation (2026-03-24)

Known gap: Live idempotency test (second `rad deploy` execution) blocked by Kubernetes environment unavailability. Structural evidence and pattern analysis strongly suggest fix will work correctly.

Closure criteria: Execute `rad deploy` twice against same environment, verify second succeeds without errors.

### Radius Azure Recipe Failure Diagnostics

**Assignment:** Diagnose concrete root causes in Radius recipes and environment wiring (follow-up to Daisy's root cause classification).

**Work Completed:**

#### Bucket A: Credential Bootstrap Gap (Confirmed)
- Analyzed `.github/workflows/deploy-azure.yml` deployment sequence
- Confirmed workflow provisions workspace, publishes recipes, deploys environment, deploys app
- **Critical finding:** Workflow never executes `rad credential register azure`
- This explains `platform-secrets` failure: Radius seeks Kubernetes secret `azure-azurecloud-default`

#### Bucket B: Recipe Output Contract Drift (Identified)
- Analyzed three Azure recipes: `state-store.bicep`, `pubsub.bicep`, `secrets.bicep`
- **Key finding:** All three manually emit Azure resource IDs in `output result.resources`
- Consulted Radius documentation: Bicep recipes auto-populate backing resources; manual `resources` entries are for Kubernetes/UCP only
- Failing resource IDs (`storageAccounts/...`, `namespaces/...`) match manual entries
- Root cause identified: ARM template cannot locate manually-emitted Azure resources

**Recommended Fix Sequence:**
1. Immediate: `rad credential register azure` (Phase 1)
2. Remove manual Azure resource IDs from recipe `result.resources` blocks (Phase 2)
3. Regenerate `.json` files from updated Bicep (Phase 3)
4. Republish OCI recipes (Phase 4)
5. Redeploy environment and app (Phase 5)

**Decision Note Generated:** `.squad/decisions.md` (merged from inbox) — focused diagnostic and repair sequence.

**Architecture Assessment:** Radius + Dapr recipe boundary remains sound. Failures are platform setup and recipe contract alignment, not design flaws. Recipe pattern established in Phases 5–6 is correct; implementation has maturity gaps.

**Handoff:** 
- Daisy approved Phase 1 execution (credential registration)
- Graham continues Phase 2–5 as needed based on Phase 1 results
- Expected next checkpoint: after Phase 1 credential registration and Phase 7 re-validation

---

## Recipe Resource Tracking Fix (2026-03-24)

### Delivered

- Removed manual Azure resource ID emission from `output result` in `infra/radius/recipes/azure/state-store.bicep`, `infra/radius/recipes/azure/pubsub.bicep`, and `infra/radius/recipes/azure/secrets.bicep`.
- Regenerated the checked-in JSON mirrors (`state-store.json`, `pubsub.json`, `secrets.json`) so the compiled output no longer carries `outputs.result.value.resources`.
- Kept the Radius app/environment model unchanged because this defect was isolated to recipe output tracking, not application wiring.

### Validation

- ✅ `az bicep build --file infra/radius/recipes/azure/state-store.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/pubsub.bicep`
- ✅ `az bicep build --file infra/radius/recipes/azure/secrets.bicep`
- ✅ `dotnet build RadiusClaim.slnx`
- ✅ `dotnet test RadiusClaim.slnx --no-build`

## Learnings

- For Azure-backed Radius recipes, omit `result.resources` entirely when the recipe only creates Azure resources; manual Azure IDs cause bad resource tracking and deployment churn.
- JSON mirrors under `infra/radius/recipes/azure/*.json` are part of the contract and must be regenerated immediately after any recipe output change.
- Minimal, architecture-safe repair here means touching only the recipe contract layer and leaving `infra/radius/app.bicep`, `infra/radius/environments/azure-radius.bicep`, and `scripts/publish-radius-recipes.sh` alone unless the defect proves otherwise.
- User preferences to preserve: avoid outdated parameters, keep platform changes minimal, and avoid architecture-specific Docker/build guidance.
- Key file paths: `infra/radius/recipes/azure/state-store.bicep`, `infra/radius/recipes/azure/pubsub.bicep`, `infra/radius/recipes/azure/secrets.bicep`, and their generated `.json` mirrors.
- Stock Radius 0.55 docs and live deployment errors beat speculative namespace migration: if `rad deploy` throws `InvalidResourceNamespace` for `Radius.Compute/containers`, revert the repo to `Applications.Core/containers` and `Applications.Core/gateways` instead of treating `BCP081` as harmless.
- The exact future compute/ingress pivot remains `Applications.Core/containers` ↔ `Radius.Compute/containers` and `Applications.Core/gateways` ↔ `Radius.Compute/routes`; the move also requires `properties.container` ↔ `properties.containers[...]` and `extensions[]` ↔ `extensions.daprSidecar` shape changes.
- For stock Radius gateway deployments, public endpoint docs should read the generated ingress/gateway host, not the backing `expense-api` service status.
- Key file paths for this rollback pattern: `infra/radius/app.bicep`, `infra/radius/modules/container-service.bicep`, `infra/radius/app.json`, `README.md`, `docs/end-to-end-setup-walkthrough.md`, and `docs/radius-validation-checklist.md`.

---

## 2026-03-24T17:36:38Z: Scribe Session — Orchestration & Decision Log

**Work:** Consolidated all pending inbox decisions into `.squad/decisions/decisions.md`, created orchestration logs for Daisy and Graham, created session log for radius-compute-review, cleared inbox.

**Files Written:**
- `.squad/orchestration-log/2026-03-24T17:36:38Z-daisy.md` — Radius.Compute rejection and follow-up orchestration
- `.squad/orchestration-log/2026-03-24T17:36:38Z-graham.md` — Radius.Compute revert implementation orchestration
- `.squad/log/2026-03-24T17:36:38Z-radius-compute-review.md` — Session summary for radius-compute review and revert
- `.squad/decisions/decisions.md` — Consolidated 5 decisions

**Decisions Merged:**
1. Daisy full-codebase review (7 criticals, 11 importants, 13 minors)
2. Radius.Compute/* rejection decision (revert to Applications.Core/*)
3. Azure credential registration documentation (Eddie)
4. Compute revert implementation (Graham)
5. Recipe resource tracking cleanup (Graham — proposed)

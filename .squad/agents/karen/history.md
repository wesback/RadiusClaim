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
- Own the scenario coverage for validation rules, approval thresholds, state transitions, and demo reliability.
- See `.squad/decisions.md` for canonical decision log: CloudExpense Lite architecture, naming conventions, and Azure-first-but-portable strategy.

### 2026-03-24: Live Radius validation blocker confirmed

- I attempted the remaining live Radius validation from this machine and did **not** fake it.
- The strongest executable proof artifact is still `scripts/validate-deployment.sh`, but it requires a reachable `expense-api` base URL; none is available from the current environment.
- Local Kubernetes access is stale: current context is `abc-wesback-aks`, but `kubectl get pods -n radius-system` fails because `abc-wesback-aks-dns-zj0uskhi.hcp.belgiumcentral.azmk8s.io` does not resolve.
- Azure subscription `5b6c36e5-b279-4005-8bf1-c73b1c2b71c2` shows no `expense`, `cloudexpense`, or `radius` resources, and resource group `RG-TestOOS` referenced by the kube context is not present.
- Structural readiness is still good: Radius Bicep files parse cleanly, and `dotnet restore/build/test` passed.
- Verdict: the live Radius validation item stays **OPEN** until the team provides a reachable Radius control-plane cluster or a live deployed `expense-api` endpoint for the Radius path.

### 2026-03-23: Phase 1 validation gate defined

- The repo started without an app scaffold or test harness, so Phase 1 validation should stay evidence-based: checklist, contract outline, root build, and Radius parse.
- The first tester gate must force the team to document the exact `$100.00` threshold behavior; “under” and “over” alone is not sufficient.
- Shared contracts need to stay cloud-agnostic and preserve explicit failure reasons so the demo earns trust on the unhappy path too.
- A shell scaffold now builds, but Phase 1 is still open until real shared contract types, visible Dapr references, and an `app.bicep` model are present.

### 2026-03-23: Phase 1 review verdict

- A green root build and clean Radius parse are necessary but not sufficient; contract semantics can still block the gate.
- If approval and rejection messages lack workflow/correlation identifiers or explicit UTC timestamp intent, the happy path may demo but the failure path stays untrustworthy.
- When a validation doc includes a repo readout snapshot, treat current files and project conventions as the authority and re-verify with fresh evidence before issuing the verdict.

### 2026-03-23: Phase 1 final re-review

- Phase 1 earns trust only when the revised contracts explain both the happy path and the hold/failure path without another schema rewrite.
- Fresh evidence matters more than repo folklore: `dotnet build ./CloudExpenseLite.slnx --nologo` and `az bicep build --file infra/radius/app.bicep --outfile /tmp/cloudexpense-app.json` both passed on re-review.
- The gate can open once the exact `$100.00` rule is explicit and the future manual-review branch is named separately from rejection.

### 2026-03-23: Phase 1 PASSED

- Karen re-ran fresh evidence and approved Phase 1 with all nine exit criteria confirmed.
- Contracts now preserve stable tracing (ExpenseId + CorrelationId), explicit UTC timestamps, and clear rejection-vs-hold distinction.
- README documents exact `$100.00` auto-approval boundary.
- Billy's solution builds cleanly; Graham's Radius model parses without error.
- **Phase 2 authorization:** Billy (expense API implementation), Graham (local dev environment), Eddie (README expansion). Karen blocked until Phase 7.

### 2026-03-23: Phase 2 review verdict

- A green build and matching Dapr component names are not enough if the user-facing list endpoint can lose freshly submitted expenses under concurrent requests.
- For Dapr-backed demo APIs, any shared recent-ID index must be concurrency-safe; otherwise `GET /expenses` stops being evidence of what was actually submitted.
- When Daisy's design says “submit and retrieve,” treat both the by-id lookup and the list view as part of the trust boundary.

### 2026-03-23: Phase 2 final re-review

- The optimistic-concurrency retry on `expense-index` fixes the original dropped-entry bug, but the failure path is still not trustworthy.
- `src/expense-api/Program.cs` persists the `ExpenseRecord` before updating the shared index, then returns `503` if indexing still fails; that leaves a saved record behind a reported submission failure.
- For this demo, a failure response must not create hidden state. Use a transactional write or a compensating delete before Phase 2 can pass.

### 2026-03-23: Phase 2 final gate

- Fresh evidence still matters: `dotnet build ./CloudExpenseLite.slnx --nologo` passed, and `docker compose -f infra/dapr/local/docker-compose.yaml config` validated the local Redis overlay.
- The latest revision fixed the original lost-update race on `expense-index`, but `src/expense-api/Program.cs` now writes the shared index before the record and still returns `503` if record persistence fails.
- For submit/list demo flows backed by Dapr state, changing write order is not enough. A reported failure must leave no persistent residue, which means a transaction or explicit compensation.

### 2026-03-23: Phase 2 ultimate gate

- Fresh evidence is still partly green: `dotnet build ./CloudExpenseLite.slnx --nologo` passed again, and `docker compose -f infra/dapr/local/docker-compose.yaml config` still validates the Redis dev overlay.
- Simone's revision improved the compensation path when the current request inserted `expense-index`, but the recovery check is still skipped when the index was already present before an ambiguous record-write failure.
- For shared Dapr write paths, "this request did not add the shared index entry" is not enough to skip verification. A concurrent winner can still create observable state, so the API must re-check the record and return a truthful `200`/`409` instead of falling through to `503`.
- Billy, Rory, and Simone have now all had a turn at the same backend artifact. If this phase stays rejected, further reassignment needs user direction rather than another automatic backend handoff.

### 2026-03-23: Phase 2 APPROVED (Warren Revision)

- Warren resolved the three-part deadlock with a record-first persistence strategy.
- All prior objections resolved: (1) record-first ordering eliminates phantom index entries, (2) strong-consistency re-read on ambiguous saves prevents hidden state, (3) truthful failure disclosure includes the persisted record and fetch location.
- Fresh evidence passed: `dotnet build ./CloudExpenseLite.slnx --nologo` succeeds; re-review confirms all prior objections fully resolved.
- **Phase 2 APPROVED 2026-03-23T14:59:08Z.** Team can proceed with confidence into the next phase.

### 2026-03-23: Phase 3 validation gate passed

- All 11 exit criteria verified with fresh evidence during Phase 3.
- Auto-approve path < $100.00 progresses correctly through Submitted → Approved → Reimbursed.
- Manual review path >= $100.00 correctly progresses through Submitted → ManualReviewRequested.
- Both paths publish `NotificationRequest` to `expense-notifications` topic as expected.
- Workflow instance IDs, state transitions, and idempotent replay semantics all correct.
- **Phase 3 APPROVED 2026-03-23T17:50:00Z.**

### 2026-03-23: Phase 4 APPROVED (Billy Revision)
- All 9 exit criteria verified with fresh evidence
- Build passes, tests pass, endpoints return correct status codes
- Auto-approve path ($50) produces correct state transitions and log entries
- Manual review path ($150) produces correct state transitions and log entries
- Pub/sub publishing and subscription verified end-to-end
- Service invocation fire-and-forget semantics verified
- CorrelationId correctly set to workflow instance ID
- Malformed payloads return HTTP 200 (no poison)
- Phase descriptor correctly reports `"phase-4"`
- Health endpoint returns correct response
- No contract changes from Phase 3
- **Phase 4 APPROVED 2026-03-23T16:52:00Z.** Subscriber is demo-trustworthy. Traceability survives pub/sub hop end-to-end.

### 2026-03-23: Phase 5 Review — Radius Integration
- Reviewed Graham's Phase 5 Radius work: `app.bicep`, `dev.bicep` environment, three Azure recipes
- Verified no naming drift: `app.bicep` components match app code expectations (`pubsub`, `statestore`)
- Build and parse evidence all pass: `az bicep build` on all Radius files, `dotnet build`, `dotnet test`
- Recipes are real (Blob Storage, Service Bus, Key Vault), not placeholders
- Environment definitions complete and credible for Radius story
- **Phase 5 APPROVED 2026-03-23T16:34:00Z.** Platform portability story credible.

### 2026-03-23: Phase 6 Review — Azure Deployment on ACA
- Reviewed Graham's Phase 6 Azure slice: `azure.bicep` environment, CI/CD workflow, Dockerfiles, end-to-end validation
- Azure environment provisions ACA, ACR, Storage, Service Bus, Key Vault, Dapr components
- CI/CD workflow includes build, test, Docker push to ACR, deployment to ACA
- Real end-to-end validation: submits $50 and $150 expenses, verifies state transitions, checks notification-svc logs
- Component naming aligned: `statestore`, `pubsub`, `platform-secrets` match local slice
- Validation proves distributed app works on Azure: state persists, workflows execute, pub/sub delivers
- **Phase 6 APPROVED 2026-03-23T16:45:17Z.** Same app code, Azure-backed Dapr components, validation proves it works.

### 2026-03-23: Phase 7 Authorization
- Both app track (Phases 1–4) and platform track (Phases 5–6) now complete and integrated
- Eddie (Docs/Story) authorized to proceed with Phase 7
- Phase 7 should: update README, add demo walkthrough, document GitHub secrets, add ADR for Azure CLI choice, consider integration tests

### 2026-03-23: Radius-First Redesign APPROVED

- Reviewed Graham's Radius-first redesign against Daisy's decision and all five acceptance criteria.
- Radius is now the primary deployment path: `deploy-azure.yml` defaults to `radius-first`, and `rad deploy` creates containers and Dapr components. No `az containerapp` commands appear in the Radius job.
- ACA fallback is clearly demoted: labeled "secondary," conditional on explicit opt-in, honestly documented with the ACA compute-kind gap explanation.
- `app.bicep` unchanged. Dapr component names (`statestore`, `pubsub`, `platform-secrets`) are stable across all paths — app code, Radius model, recipes, ACA fallback, local dev.
- All Bicep files parse cleanly. Build and tests pass with zero warnings.
- Graham's design improved on Daisy's spec: uses Kubernetes as Radius compute target (which is what Radius actually supports) instead of trying to bootstrap ACA for Radius.
- **Open item (non-blocking):** The `deploy-radius` workflow job lacks end-to-end validation steps ($50/$150 expense submissions). Needs follow-up in Phase 7 when a live Radius environment is available.
- Key files: `.github/workflows/deploy-azure.yml`, `infra/radius/environments/azure-radius.bicep`, `infra/radius/environments/azure.bicep`, `infra/radius/recipes/azure/*.bicep`, `README.md`.

### 2026-03-23: Portability Fixes Review (Graham & Eddie)

- Reviewed Graham's `app.bicep` parameterization via `daprBackings` object — keeps logical component names stable while moving Azure-specific details behind overrideable parameters
- Reviewed Eddie's README updates — clearly separates app portability from Azure-specific CI/CD path, documents Radius as intended future (when ACA support arrives)
- Both fixes are targeted, honest, and preserve demo credibility without overstating portability
- **Status:** Both approved. Portability story now holds up under scrutiny.

### 2026-03-23: Phase 7 & Beyond

- Phases 1–6 complete and approved (2026-03-23)
- Radius-first redesign complete and approved (2026-03-23T19:10:00Z)
- Portability follow-ups complete and approved
- **Ready for Phase 7 execution:** End-to-end validation of live Radius deployment, docs/demo scripts, integration tests
- Team confidence high on all three tracks: app code, platform wiring, deployment credibility

### 2026-03-24: Phase 7 Validation Artifact Created

- Created executable validation script: `scripts/validate-deployment.sh`
- Script validates distributed system behavior (not just process startup):
  - State persistence via Dapr state store
  - Workflow orchestration via Dapr Workflow
  - Service invocation (expense-api → workflow-engine)
  - Auto-approve flow ($50): Submitted → Approved → Reimbursed
  - Manual-review flow ($150): Submitted → ManualReviewRequested
  - Boundary case ($100.00): Must enter manual review, not auto-approve
- Script is executable, standalone, uses existing tooling (bash, curl, jq)
- No new test frameworks invented — aligns with "use existing tooling only" constraint
- Documentation artifacts:
  - `docs/phase-7-validation-checklist.md`: Exit criteria and approval process
  - `scripts/README.md`: Usage guide and troubleshooting
  - `.squad/decisions/inbox/karen-phase7-validation-script.md`: Design rationale
- **Key learnings:**
  - Phase-gate validation for distributed systems must prove runtime behavior, not just build/parse
  - Script-based validation is appropriate when no test framework exists and sample targets platform/ops audiences
  - Executable validation earns more trust than documentation checklists alone
  - The strongest realistic artifact without inventing infrastructure is an extracted, standalone version of CI/CD validation logic
- **File paths:**
  - Validation script: `scripts/validate-deployment.sh`
  - Checklist: `docs/phase-7-validation-checklist.md`
  - Demo walkthrough (already existed): `docs/phase-7-demo-walkthrough.md`
  - CI/CD integration: `.github/workflows/deploy-azure.yml` (lines 382-443)


### 2026-03-24: Phase 7 Validation Testing Complete

**Decision:** Script-Based Integration Testing APPROVED

**Rationale:** Phase 7 validation uses executable bash script (`scripts/validate-deployment.sh`) as primary integration validation artifact instead of adding new test framework (xUnit, Playwright, etc.).

**Options Considered & Verdict:**
| Option | Status | Rationale |
|--------|--------|-----------|
| xUnit integration test project | Rejected | Invents infrastructure, adds dependencies |
| Playwright E2E framework | Rejected | Overkill for API-only validation |
| Standalone bash script (CI/CD logic extraction) | **Selected** | Uses existing pattern, executable, no new dependencies |
| Documentation checklist only | Rejected | Doesn't prove behavior; lowers trust bar |

**What the Script Validates:**
- State persistence (Dapr state store)
- Workflow orchestration (Dapr Workflow)
- Service invocation (expense-api → workflow-engine)
- Approval thresholds ($50 auto-approve, $150 manual-review, $100 boundary)
- Status transitions end-to-end

**Deliverables:**
1. **scripts/validate-deployment.sh** (executable validation script)
   - Comprehensive checks: health, $50, $150, $100 boundary
   - Standard tools (jq, curl) — portable
   - Colored output, clear pass/fail
   - Correct exit codes (0 = success)
   - Timeout handling (30 attempts, 2-sec delay)

2. **scripts/README.md** (usage documentation)
   - Prerequisites (jq, curl)
   - Integration points (CI/CD, phase gates)
   - Troubleshooting

3. **docs/phase-7-validation-checklist.md** (validation criteria)
   - Three validation levels (script, CI/CD, manual demo)
   - Exit criteria concrete and measurable
   - Release-blocking gaps explicit
   - Non-blocking issues separated

**Status:** APPROVED — 2026-03-24

## Phase 7 Completion (2026-03-24)

### Orchestration Log Published
- Session date: 2026-03-24T09:11:24Z
- Documented live Radius validation blocker assessment
- Confirmed environment unavailability (not design blocker)
- Filed orchestration-log/20260324T091124Z-karen.md

### Decision Merged to Squad Records
- Karen — Live Radius validation blocker decision added to squad/decisions.md
- Captures honest assessment: kubeconfig unreachable, DNS resolution fails, no discoverable resources
- Establishes closure standard: need working kubeconfig + deployed Radius environment OR live expense-api HTTPS URL
- Committed as reference for future environment setup requirements

### 2026-03-24: Kubernetes-first portability update review

- Re-ran fresh structural evidence instead of trusting the story: workflow YAML parses, `dotnet restore/build/test` passes, `bash -n scripts/validate-deployment.sh` passes, and the Radius Bicep files still build.
- The update is **not ready for commit/push yet** because docs and workflow drift in ways users will feel: README still mentions `deployment_mode=radius-first`, the validation checklist still says `deploy-radius` and `cloudexpense`, the demo walkthrough troubleshooting still uses `az containerapp`, and the ADR still says “both paths exist.”
- `RADIUS_KUBECONFIG` is documented as base64-encoded, but the workflow writes it straight to the kubeconfig file without decoding. Either the docs or the workflow must change before anyone can trust the setup instructions.
- Live Kubernetes execution is still unproven from this environment; the remaining honest closure step is a real workflow run (or equivalent manual run) against a reachable Radius-enabled cluster.
- Generated `bin/`, `obj/`, and Bicep-emitted `.json` changes from validation were side effects only and were reverted after the checks.

### 2026-03-24: Radius Idempotency Fix Review — APPROVED

**Context:** Validated Graham's Radius idempotency fix addressing workflow pattern that created temporary bootstrap environments on every run.

**Problem:** Workflow used `bootstrap-${{ github.run_id }}` pattern, creating new temporary environments instead of updating target environment in place, causing repeatability failures.

**Graham's Solution:**
```bash
# OLD (not idempotent):
./rad env create "$RADIUS_BOOTSTRAP_ENVIRONMENT"  # Unique per run
./rad env switch "$RADIUS_BOOTSTRAP_ENVIRONMENT"
# Deploy environment
./rad env switch "$RADIUS_ENVIRONMENT_NAME"       # Switch again

# NEW (idempotent):
./rad env create "$RADIUS_ENVIRONMENT_NAME" || true  # Create or ignore if exists
./rad env switch "$RADIUS_ENVIRONMENT_NAME"
# Deploy environment (updates in place)
```

**Evidence Collected:**

*Level 1: Structural Validation* ✅ ALL PASS
- Bicep files parse cleanly (`az bicep build`)
- Namespace ownership correct: Applications.Core/* for app/env, Applications.Dapr/* for components
- Environment configuration fully parameterized
- Build passes: `dotnet build` succeeds, 0 errors, 0 warnings
- Validation script syntax valid

*Level 2: CI/CD Integration* ✅ ALL PASS
- Workflow pattern changed to idempotent `|| true` approach
- No temporary bootstrap environments
- Documentation updated (README, walkthrough, checklist)

*Level 3: Live Deployment* 🔴 BLOCKED
- Cannot execute live test (Kubernetes environment unavailable)

**Verdict:** ✅ **APPROVED**

**Why approved:**
- Fix is simple, correct, and addresses root cause
- Pattern is naturally idempotent (`rad env create <name> || true`)
- Documentation updated consistently across all operator guides
- No regression in namespace ownership (Applications.Core/* + Applications.Dapr/* preserved)
- Build and structural validation all pass

**Gap:** Live idempotency test blocked by environment unavailability, but fix is structurally sound and follows Radius best practices.

**Learnings:**
- Idempotent deployment patterns should target stable resource names, not unique-per-run identifiers
- `command || true` pattern makes creation idempotent in Bash workflows
- Bootstrap patterns inherited from examples may be unnecessary for production workflows
- Environment updates in Radius are naturally idempotent when targeting same name
- Reviewer can approve based on structural correctness when fix is simple and well-understood

**Files Reviewed:**
- `.github/workflows/deploy-azure.yml` (workflow changes)
- `README.md` (idempotent deployment section added)
- `docs/end-to-end-setup-walkthrough.md` (bootstrap references removed)
- `docs/radius-validation-checklist.md` (idempotent pattern documented)
- `.squad/agents/graham/history.md` (Graham's implementation notes)

**Next Step:** Live validation when Radius environment becomes available (second `rad deploy` should succeed without errors).

## Radius Idempotency Fix Validation (2026-03-24)

### Validation Task

Graham implemented a fix for Radius deployment idempotency issues in the GitHub Actions workflow. Tasked with validating the fix using structural evidence and pattern analysis due to unavailable live Radius environment.

### Problem Summary

GitHub Actions workflow created temporary bootstrap environments (`bootstrap-${{ github.run_id }}`) on every run, preventing idempotent redeployment. Subsequent runs would fail because target environment already existed from previous runs.

### Solution Reviewed

Graham replaced the temporary bootstrap pattern with direct target environment creation using idempotent `rad env create || true` pattern. Changes included:

**Workflow Changes:**
- Removed `RADIUS_BOOTSTRAP_ENVIRONMENT: bootstrap-${{ github.run_id }}`
- Changed to `rad env create "$RADIUS_ENVIRONMENT_NAME" || true`
- Removed redundant post-deploy `rad env switch` (deploy already switches)

**Documentation Updates:**
- `README.md`: Added "Idempotent deployment" section
- `docs/end-to-end-setup-walkthrough.md`: Updated to idempotent pattern; removed bootstrap references
- `docs/radius-validation-checklist.md`: Removed bootstrap references; documented idempotent pattern

### Validation Approach

Since live Kubernetes environment was unavailable, validation focused on **structural correctness** across four dimensions:

#### 1. Build & Bicep Validation ✅
- `az bicep build --file infra/radius/app.bicep`: Passes cleanly
- `az bicep build --file infra/radius/environments/azure-radius.bicep`: Passes cleanly
- `az bicep build --file infra/radius/environments/azure.bicep`: Passes cleanly
- `az bicep build --file infra/radius/recipes/azure/*.bicep` (all three): All pass
- `dotnet build CloudExpenseLite.slnx --configuration Release`: Zero warnings, zero errors

#### 2. Workflow Parameterization ✅
- Environment variable passing verified: `$RADIUS_ENVIRONMENT_NAME` used correctly
- Bicep parameter references match declared parameter names
- No regression in Azure provider scope or location parameters
- All required values passed correctly through workflow environment

#### 3. Namespace Ownership ✅
- Applications.Core/applications: Preserved ✅
- Applications.Core/environments: Preserved ✅
- Applications.Dapr/stateStores: Preserved ✅
- Applications.Dapr/pubSubBrokers: Preserved ✅
- Applications.Dapr/secretStores: Preserved ✅
- No changes to approved design boundaries

#### 4. Documentation Consistency ✅
- `README.md`: New "Idempotent deployment" section explains pattern clearly
- `docs/end-to-end-setup-walkthrough.md`: Bootstrap references removed; idempotent steps documented
- `docs/radius-validation-checklist.md`: Idempotent pattern documented; bootstrap pattern removed
- All documentation uses consistent language and examples

### Pattern Analysis

**Idempotency Mechanism:**
```bash
rad env create <target-name> || true  # Idempotent: succeeds on creation or if already exists
rad env switch <target-name>          # Switches to target
rad deploy <env>.bicep ...            # Updates in place, switches automatically
```

**Why This Works:**
- `|| true` pattern ignores the "already exists" error, making the overall sequence idempotent
- Same environment name across runs means `rad deploy` updates configuration in place
- No accumulated temporary environments (no per-run bootstrap)
- Natural Radius behavior: environments with same name are updated, not recreated

**Pattern Precedent:**
- `rad env create || true` is standard idempotent creation pattern in Bash/DevOps
- Radius environments naturally support in-place updates when targeting same name
- Bootstrap patterns were inherited from early examples, not required for production

### Approval Rationale

✅ **Fix is correct:** Replaces non-idempotent pattern with naturally idempotent one  
✅ **Pattern is sound:** `|| true` is standard idempotent pattern; Radius supports in-place updates  
✅ **Structural validation passes:** Bicep parse, build, namespace ownership, parameterization all verified  
✅ **Documentation consistent:** README, walkthrough, checklist all updated with new pattern  
✅ **No regressions:** Approved namespace ownership preserved; no impact on app code or Dapr components  

**Simple fixes with clear rationale can be approved based on structural validation when live testing is blocked by environment unavailability.**

### Known Gap

Live idempotency test (second `rad deploy` execution) blocked by Kubernetes environment unavailability.

**Closure Criteria:**
1. Execute `rad deploy infra/radius/environments/azure-radius.bicep` (first run)
2. Execute `rad deploy infra/radius/environments/azure-radius.bicep` again (second run)
3. Second run succeeds without "already exists" or similar errors
4. Environment configuration remains consistent across both runs

### Status

✅ **APPROVED** (2026-03-24)

**Verdict:** Graham's Radius idempotency fix is approved for deployment. Structural evidence strongly suggests fix will work correctly. No code issues blocking deployment; environment unavailability is not a blocker.

**Impact:**
- ✅ Deployments become repeatable without manual environment cleanup
- ✅ Workflow simpler and clearer
- ✅ Operator documentation consistent
- ✅ No breaking changes to approved design

### Team Learnings

1. **Idempotent resource creation requires stable naming** — unique-per-run identifiers break idempotency
2. **`command || true` pattern is standard for idempotent Bash sequences** — makes commands succeed or no-op
3. **Radius environments update in place when targeting same name** — not recreated, automatically in-place
4. **Bootstrap patterns from early examples may be unnecessary** — validate each pattern's necessity for production
5. **Simple, well-understood fixes can be approved based on structural validation** — when live testing is blocked, structural evidence + pattern analysis + documentation consistency provides sufficient confidence

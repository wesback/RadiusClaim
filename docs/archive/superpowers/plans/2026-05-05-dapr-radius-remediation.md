# Dapr + Radius Trustworthiness Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make RadiusClaim a trustworthy, portable Dapr + Radius sample by removing approval auth drift, fixing write-path consistency, and realigning the Radius model, bootstrap flow, tests, and docs around one anonymous approval contract.

**Architecture:** Keep Dapr as the app boundary and Radius/Bicep as the platform source of truth. Approval endpoints stay anonymous by design, so durable approval state must be written by workflow-owned transitions after successful signaling, not by pre-emptive API writes or token-based guards. Remove raw service URL assumptions and keep Azure-specific concerns in recipes/bootstrap, not in service code.

**Tech Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius Bicep, bash automation, GitHub Actions, xUnit

---

## Executive Summary

- **Must-fix:** remove the `APP_API_TOKEN` / `dapr-api-token` approval gate in `src/workflow-engine/Program.cs` and stop testing/documenting approval auth as a requirement.
- **Must-fix:** make approval/rejection write paths truthful in `src/expense-api/Program.cs` and workflow activities so failed workflow signaling cannot leave expense state in a partially approved/rejected shape.
- **Must-fix:** remove non-portable service URL wiring from `infra/radius/app.bicep` and treat Dapr app IDs + Radius connections as the only service contract the sample teaches.
- **Must-fix:** realign `README.md`, `scripts/bootstrap.sh`, `scripts/apply-dapr-components-from-recipes.sh`, portability checks, and CI so the repository has one platform story instead of several competing ones.
- **Must-fix:** repair the broken test gate (`src/ExpenseApi.Tests/OAuth2AuthenticationTests.cs`, `src/NotificationSvc.Tests/Templates/TemplateRendererTests.cs`) before trusting any CI verdict.
- **Nice-to-have:** once the contract is repaired, trim or repurpose auth-focused docs that no longer help the sample tell the Dapr + Radius story.

## Workstreams

1. **Workstream 1 — Approval Contract & Truthful Persistence (Must-fix)**  
   Outcome: anonymous approval endpoints with no token validation anywhere on the approval path; state changes happen only after workflow signaling is accepted and workflow-owned transitions run.
2. **Workstream 2 — Radius App Model Portability Alignment (Must-fix)**  
   Outcome: `infra/radius/app.bicep` stops teaching raw Kubernetes/DNS URL coupling and reflects the Dapr-first invocation contract.
3. **Workstream 3 — Bootstrap / Recipe / Namespace Contract Alignment (Must-fix)**  
   Outcome: scripts and recipes agree on Key Vault naming, namespace expectations, and the current two-phase Dapr component projection flow.
4. **Workstream 4 — Test & CI Gate Rehabilitation (Must-fix)**  
   Outcome: unit/integration tests compile, portability checks detect current drift, and `.github/workflows/deploy-azure.yml` runs the right gates.
5. **Workstream 5 — Docs & Demo Narrative Realignment (Must-fix)**  
   Outcome: README and supporting docs describe the sample honestly: anonymous approvals, workflow-owned durability, Radius as source of truth, Azure recipes as explicit platform detail.
6. **Workstream 6 — Optional Cleanup (Nice-to-have)**  
   Outcome: reduce leftover auth/security narrative and dependency noise only after the must-fix contract is stable.

## Detailed Tasks (per workstream)

### Workstream 1: Approval Contract & Truthful Persistence

**Files:**
- Modify: `src/expense-api/Program.cs`
- Modify: `src/workflow-engine/Program.cs`
- Modify: `src/workflow-engine/Workflows/ExpenseApprovalWorkflow.cs`
- Modify: `src/workflow-engine/Models/ManualDecisionEvent.cs`
- Modify: `src/workflow-engine/Models/RejectionInput.cs`
- Modify: `src/workflow-engine/Activities/RecordApprovalActivity.cs`
- Modify: `src/workflow-engine/Activities/RejectExpenseActivity.cs`
- Modify if needed: `src/shared/RadiusClaim.Contracts/ExpenseRecord.cs`
- Test: `src/ExpenseApi.Tests/OAuth2AuthenticationTests.cs`
- Test: `src/WorkflowEngine.Tests/Activities/ApproveExpenseActivityTests.cs`
- Test: `src/IntegrationTests/ActivityChain/ExpenseWorkflowActivityChainTests.cs`

- [ ] Add failing API tests that prove `POST /expenses/{id}/approve` and `POST /expenses/{id}/reject` are anonymous by design and do not require bearer tokens, app roles, or API tokens.
- [ ] Add failing API tests for truthful failure paths: workflow `404`, `409`, and downstream invocation failures must not mutate `ExpenseRecord.Status`, `ApprovedBy`, `ApprovedAt`, or `RejectionReason` in the state store.
- [ ] Remove `APP_API_TOKEN` / `dapr-api-token` validation and the non-development fail-closed behavior from `src/workflow-engine/Program.cs`; the `/workflows/{instanceId}/decide` path must accept the workflow decision without a secret contract.
- [ ] Refactor `HandleExpenseApprovalActionAsync` in `src/expense-api/Program.cs` so it signals the workflow first and never writes approval/rejection audit state before the signal succeeds.
- [ ] Move durable manual-decision persistence into workflow-owned transitions by extending `ManualDecisionEvent`, `RejectionInput`, `RecordApprovalActivity`, and `RejectExpenseActivity` as needed.
- [ ] Lock the anonymous audit contract up front: keep workflow-owned decision timestamps and rejection reasons if they help the demo, but do **not** claim a verified reviewer identity. Preferred implementation: stop persisting authenticated-identity semantics (`ApprovedBy`) for anonymous approvals, or leave the field null and mark it non-authoritative in the sample.
- [ ] Remove or soften the self-approval story in code/comments/docs. In an anonymous sample, a fake identity check is misleading unless a real identity contract still exists.
- [ ] Re-run focused suites: `dotnet test src/WorkflowEngine.Tests/WorkflowEngine.Tests.csproj --nologo --tl:off`, `dotnet test src/IntegrationTests/IntegrationTests.csproj --nologo --tl:off`, and the repaired expense API tests.

### Workstream 2: Radius App Model Portability Alignment

**Files:**
- Modify: `infra/radius/app.bicep`
- Review for impact: `src/shared/RadiusClaim.Dapr/RadiusClaimDapr.cs`
- Review for impact: `src/expense-api/Program.cs`
- Review for impact: `src/workflow-engine/Program.cs`
- Validate: `infra/radius/environments/azure-radius.bicep`

- [ ] Remove the hardcoded `expenseApi` connection source (`http://expense-api:8080`) from `infra/radius/app.bicep`.
- [ ] Replace that edge with the smallest truthful contract: either no explicit Radius connection at all (if the code already uses Dapr app IDs) or a config value that carries an app ID/name rather than a URL.
- [ ] Review `azureAdAuthority` / `azureAdAudience` defaults in `infra/radius/app.bicep` against the new anonymous approval contract. If they no longer support an active sample behavior, cut them; if retained for non-approval scenarios, soften the surrounding claims so they are not presented as part of the approval flow.
- [ ] Keep the public surface small: `expense-api` stays the only public gateway; `workflow-engine` and `notification-svc` remain internal and Dapr-addressable.
- [ ] Validate the app/environment model after edits with `az bicep build --file infra/radius/app.bicep` and `az bicep build --file infra/radius/environments/azure-radius.bicep`.

### Workstream 3: Bootstrap / Recipe / Namespace Contract Alignment

**Files:**
- Modify: `scripts/bootstrap.sh`
- Modify: `scripts/apply-dapr-components-from-recipes.sh`
- Modify: `infra/radius/recipes/azure/secrets.bicep`
- Review for collateral updates: `scripts/README.md`
- Review for collateral updates: `README.md`
- Test: `tests/portability/dapr-components-loaded.sh`
- Test: `tests/portability/README.md`

- [ ] Replace the Key Vault name prediction in `scripts/bootstrap.sh` (`ce-*`) with logic that matches `infra/radius/recipes/azure/secrets.bicep` (`kvrc{suffix}`), or better, resolve the name from recipe metadata instead of shadowing the formula.
- [ ] Audit `scripts/apply-dapr-components-from-recipes.sh` so it consumes the same component names and Azure metadata that the recipe outputs advertise; keep Radius recipe metadata as the source of truth.
- [ ] Align namespace defaults across scripts and checks on **`radiusclaim-azure`** as the canonical namespace when no override is supplied. That matches `scripts/bootstrap.sh`, `README.md`, and `.github/workflows/deploy-azure.yml`; `azure-radiusclaim` should be treated as stale drift to remove.
- [ ] Remove stale references to superseded component deployment flows (`deploy-dapr-components.sh` or equivalent) when the supported path is now `apply-dapr-components-from-recipes.sh`.
- [ ] Keep Kubernetes-specific behavior explicit and abstracted: scripts may operate on a namespace because Radius deploys to Kubernetes, but they should derive that namespace from the Radius/environment contract instead of stale literals.
- [ ] Re-run bash/static validation after edits: `bash -n scripts/bootstrap.sh`, `bash -n scripts/apply-dapr-components-from-recipes.sh`.

### Workstream 4: Test & CI Gate Rehabilitation

**Files:**
- Modify: `.github/workflows/deploy-azure.yml`
- Modify: `tests/portability/run-all.sh`
- Modify: `tests/portability/README.md`
- Modify: `tests/portability/dapr-components-loaded.sh`
- Modify: `tests/portability/recipes-are-complete.sh`
- Modify: `tests/portability/bootstrap-idempotency.sh`
- Modify: `tests/portability/region-agnostic.sh`
- Modify: `src/ExpenseApi.Tests/OAuth2AuthenticationTests.cs`
- Modify: `src/NotificationSvc.Tests/Templates/TemplateRendererTests.cs`
- Add tests as needed under: `src/ExpenseApi.Tests/`, `src/WorkflowEngine.Tests/`, `src/IntegrationTests/`

- [ ] Repair the compile blockers in `src/ExpenseApi.Tests/OAuth2AuthenticationTests.cs` (stale Dapr mocks and nonexistent `StartWorkflowAsync`) so the solution can build under `dotnet test` again.
- [ ] Repair the malformed `src/NotificationSvc.Tests/Templates/TemplateRendererTests.cs` file so `NotificationSvc.Tests` compiles and the existing template behavior is actually gated.
- [ ] Replace old approval-auth assertions with tests that encode the desired anonymous approval contract and truthful failure semantics.
- [ ] Add a regression test that covers the real manual-review race: decision accepted first, workflow activity later persists the final state, and failure branches do not leave a pre-written approval.
- [ ] Update portability checks so they catch current drift instead of passing falsely:
  - raw service URLs in `infra/radius/app.bicep`
  - stale namespace defaults in `tests/portability/dapr-components-loaded.sh`
  - stale script names in docs/tests
  - recipe/bootstrap naming mismatches for Key Vault handling
- [ ] Update `.github/workflows/deploy-azure.yml` so the workflow runs the repaired .NET test gate plus `bash tests/portability/run-all.sh`; do not let “all checks passed” mean “static checks skipped or stale checks green.”
- [ ] Use these commands as the minimum release gate: `dotnet test RadiusClaim.slnx --nologo --tl:off`, `bash tests/portability/run-all.sh`, `az bicep build --file infra/radius/app.bicep`, and `az bicep build --file infra/radius/environments/azure-radius.bicep`.

### Workstream 5: Docs & Demo Narrative Realignment

**Files:**
- Modify: `README.md`
- Modify or repurpose: `docs/API_AUTHENTICATION.md`
- Review for related drift: `docs/GETTING_STARTED.md`
- Review for related drift: `docs/end-to-end-setup-walkthrough.md`
- Review for related drift: `docs/radius-validation-checklist.md`

- [ ] Rewrite the approval narrative so the sample clearly says approvals are anonymous by design in this repo; do not tell readers to re-enable API keys or approval token validation to make the sample “correct.”
- [ ] Soften security claims instead of overpromising. **Correct framing:** this repo is a Dapr + Radius portability sample, not a security reference implementation.
- [ ] Remove or rewrite `docs/API_AUTHENTICATION.md` content that currently describes approval scopes, approver roles, and protected approval endpoints. If any auth guidance remains for other experiments, explicitly mark it as out-of-scope for the sample’s approval flow.
- [ ] Update README deployment/validation commands so script names, namespace names, and Dapr component instructions match the current bootstrap path.
- [ ] Update workflow explanation text to match the corrected persistence order: API submits a decision, workflow owns the durable transition, and failures do not create partially approved state.
- [ ] Re-read docs after edits to ensure the platform story can be taught in ten minutes without detouring into unused security mechanisms.

### Workstream 6: Optional Cleanup

**Files:**
- Review: `docs/CONSOLIDATION_REPORT.md`
- Review: `README.md`
- Review: project files with OpenTelemetry dependency warnings

- [ ] **Nice-to-have:** trim leftover auth/security prose that survives only as historical baggage once the anonymous approval contract is settled.
- [ ] **Nice-to-have:** decide whether `ApprovedBy` / `ApprovedAt` field names still read honestly for both approvals and rejections; rename only if the team agrees the contract is materially misleading.
- [ ] **Nice-to-have:** schedule a separate dependency-maintenance issue for the OpenTelemetry vulnerability warnings surfaced by `dotnet test`; keep it out of the approval-remediation scope unless it blocks the demo.

## Sequencing / Dependencies

1. **Lock the target contract first (Workstreams 1 + 2 design decisions).**  
   Decide the approval truth model, the app-model invocation contract, and the canonical default namespace (`radiusclaim-azure`) before changing scripts or docs.
2. **Repair the broken test harness next (Workstream 4 compile blockers).**  
   A failing test project makes every later change harder to trust.
3. **Implement approval-path behavior changes (Workstream 1).**  
   This is the correctness core: anonymous approval semantics plus truthful persistence ordering.
4. **Bring the Radius model and bootstrap flow back into alignment (Workstreams 2 + 3).**  
   Once service behavior is correct, fix the platform contract so the sample teaches the same story the code now tells.
5. **Rebuild CI/static gates around the corrected contract (Workstream 4 remaining tasks).**  
   Make the pipeline fail for the drift that produced this remediation plan.
6. **Update docs last (Workstream 5).**  
   Documentation should describe the settled implementation, not lead it.
7. **Optional cleanup only after green gates.**  
   Nice-to-have cleanup must not delay the must-fix remediation.

## Definition of Done

- Approval/rejection remains anonymous by design across code, tests, workflow endpoints, and docs.
- No approval-path token validation remains in `src/workflow-engine/Program.cs`; no API key or `dapr-api-token` contract is required anywhere on the approval path.
- `src/expense-api/Program.cs` no longer persists approval/rejection state before successful workflow signaling.
- Workflow-owned activities are the only place that persist manual approval/rejection state, and failure branches do not leave inconsistent `ExpenseRecord` data behind.
- `infra/radius/app.bicep` no longer hardcodes `http://expense-api:8080` or other Kubernetes/DNS URL assumptions for app-to-app behavior.
- `scripts/bootstrap.sh`, `scripts/apply-dapr-components-from-recipes.sh`, and `infra/radius/recipes/azure/secrets.bicep` agree on Key Vault naming and namespace/component contracts.
- `.github/workflows/deploy-azure.yml` runs a meaningful gate: repaired `dotnet test`, repaired portability checks, and Bicep builds.
- `dotnet test RadiusClaim.slnx --nologo --tl:off` passes.
- `bash tests/portability/run-all.sh` passes for the right reasons (no stale namespace/script false positives or false greens).
- `README.md` and supporting docs describe one coherent sample story: Dapr app IDs + Radius app model + Azure-backed recipes, with anonymous approvals and truthful write semantics.

## Optional Improvements

- **Nice-to-have:** add a tiny ADR explaining why anonymous approvals are intentional for this sample and why security hardening is deliberately out of scope.
- **Nice-to-have:** add one focused end-to-end test that exercises manual approval from `expense-api` through workflow completion with mocked Dapr invocation boundaries.
- **Nice-to-have:** collapse or archive auth-heavy docs that no longer serve the sample after this remediation.

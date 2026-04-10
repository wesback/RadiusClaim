- Always check both the infra wiring AND the registry visibility when debugging pull failures.
- Dead contracts in RadiusClaim.Contracts (`ExpenseApproved.cs`, `ExpenseRejected.cs`) and unused enum values (`ExpenseSubmitted`, `ApprovalTimeout`, `ExpenseRejectedTimeout`) — these predate the `NotificationRequest`/`NotificationEventType` design and should be removed before blog post publication.
- Phase metadata strings (`"phase-3"`, `"phase-5"`) are exposed by the `GET /` service descriptor on each service. These are development scaffolding and should be stripped from the final sample.
- Workflow activities (`ApproveExpenseActivity`, `ProcessReimbursementActivity`, `RecordApprovalActivity`, `RejectExpenseActivity`) use the default Dapr `ConsistencyMode` (eventual) while expense-api explicitly uses `ConsistencyMode.Strong`. Deciding and documenting the intended consistency model matters for a reference sample.
- The bare `catch when (!cancellationToken.IsCancellationRequested) { }` in `TryCreateExpenseRecordAsync` silently swallows all exceptions — should log the exception at Warning level as a teaching example.
- README architecture diagram lists a `ValidateExpense` activity that doesn't exist in code. The actual activities are `ApproveExpense`, `ProcessReimbursement`, `PublishNotification`, `RecordApproval`, `RejectExpense`.
- `app.Logger` is used inside inline middleware lambdas in both expense-api and workflow-engine. Should use an injected `ILogger<Program>` for a meaningful log category.
- `docs/` folder contains development-phase artifacts (`phase-7-*`, `phase7-*`) that expose build sequencing to external readers. These should be removed or renamed.
- `StateStore` and `PersistentStore` are identical aliases in `RadiusClaimDapr.Components` — legacy artifact, one should be removed.

---

## 2026-03-28: Frontend Architectural Review

### Context
Wesley requested a full frontend review covering architecture, state management, styling, testing, performance, accessibility, and documentation.

### Key Findings

**Frontend Architecture:** Vanilla JS/CSS served from `src/expense-api/wwwroot/app/` (3 files: `index.html`, `app.js` 643 lines, `styles.css` 655 lines). No framework, no build step. This is intentional — the UI exists to demo the distributed workflow, not frontend patterns.

**Strengths:**
- Clean API decoupling — all data via REST endpoints (`/expenses`, `/expenses/{id}/workflow`)
- Centralized state object with render functions (no direct DOM mutation from state)
- Semantic HTML with good ARIA foundation (skip-link, live regions, aria-labelledby)
- CSS custom properties provide design tokens
- Zero dependencies = instant load, no node_modules

**Gaps Identified:**
- No frontend tests (JS or e2e)
- Design tokens undocumented in CSS
- Form validation errors not wired to `aria-describedby`
- Color contrast not audited
- No architecture comment in `app.js`

### Recommendations

**Must-Fix (3 items):**
1. Document design tokens at top of `styles.css`
2. Wire form errors to `aria-describedby`
3. Add header comment to `app.js` explaining data flow

**Nice-to-Have (4 items):**
4. Group CSS by component
5. Audit color contrast (WCAG AA)
6. Add basic Playwright smoke test
7. Extract state mutations to named functions

**Future (3 items if UI grows):**
8. Consider TypeScript
9. Add pagination to expense list
10. Generate TS types from C# contracts

### Architectural Verdict
**Fit for purpose.** No architectural changes required. The vanilla JS approach is appropriate — a framework would obscure the Dapr story. Main gaps are documentation and accessibility polish, addressable in a single PR.

### Decision Document
Written to: `.squad/decisions/inbox/daisy-frontend-review.md`

---

## 2026-04-03: Container Termination RCA — Azure Storage Authorization Failure

### Problem Statement
Wesley reported deployment failure with three service containers crashing:
- expense-api: daprd in CrashLoopBackOff
- workflow-engine: daprd in CrashLoopBackOff  
- notification-svc: daprd in CrashLoopBackOff

Initial report said "image conflict with kubectl-set" and "no message" errors.

### Investigation Results

✅ **Images are healthy** — All pull successfully, app containers run
✅ **Cluster is healthy** — Dapr system, Kubernetes system, Radius system all running
✅ **Root cause identified** — Dapr component authorization failure

**Actual root cause:** Dapr's `statestore` component (state.azure.blobstorage/v1) fails to initialize because the `radiusclaim-workload-identity` managed identity has **zero role assignments** on the storage account.

Daprd starts, attempts to load the `statestore` component, gets a 403 AuthorizationFailure when trying to create the `expense-state` container, logs the error, and shuts down gracefully (exiting the pod).

### Key Findings

1. **Dapr component config lacks auth method** — Only has accountName, containerName, tenantId. No `useAAD: true` or auth credentials.

2. **Managed identity has no Storage roles** — `az role assignment list --scope $STORAGE_ACCOUNT --query "[?principalName=='radiusclaim-workload-identity']"` returns empty.

3. **Service accounts lack workload identity annotations** — No `azure.workload.identity/client-id` labels on expense-api, workflow-engine, notification-svc service accounts.

4. **Component scope is namespace-level** — All three services reference the same `statestore` component, so all three fail identically.

### Why "No Message" Error?

The Kubernetes event truncated the actual error. Full message from daprd logs: `403 This request is not authorized to perform this operation. ERROR CODE: AuthorizationFailure` when attempting `PUT https://statercdfgrvmc2tvmlc.blob.core.windows.net/expense-state`.

### Recommendation for Wesley

**Assign Storage Blob Data Contributor to workload identity:**
```bash
IDENTITY_PRINCIPAL=$(az identity show -g radiusclaim-rg -n radiusclaim-workload-identity --query 'principalId' -o tsv)
STORAGE_SCOPE=$(az storage account show -n statercdfgrvmc2tvmlc -g radiusclaim-rg --query 'id' -o tsv)

az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee-object-id "$IDENTITY_PRINCIPAL" \
  --scope "$STORAGE_SCOPE"

rad deploy infra/radius/app.bicep
```

### Architectural Insight

This is a **bootstrap sequencing and validation gap**, not a design flaw. The `deploy-dapr-components-workload-identity.sh` script should:
1. Verify all Azure components (Key Vault, Storage, etc.) exist
2. Verify managed identity has the required roles
3. Add annotations to service accounts linking them to the managed identity
4. Create role assignments if missing

The script may have assumed resources existed or skipped role creation due to a pre-flight check.

### Decision Document

Written to: `.squad/decisions/inbox/daisy-bootstrap-container-failure-rca.md`

---

## 2026-04-03: OpenTelemetry Exporter Jaeger Version Constraint Analysis

### Problem Statement
Docker build fails during `dotnet restore` for all three services (expense-api, workflow-engine, notification-svc) with:
- `error NU1102: Unable to find package OpenTelemetry.Exporter.Jaeger with version (>= 1.11.0)`
- `warning NU1902: Package 'OpenTelemetry.Api' 1.11.1 has a known moderate severity vulnerability`

### Root Cause Identified
The **OpenTelemetry ecosystem has fragmented release cadences**:
- Core packages (OpenTelemetry, Instrumentation.*) reached 1.11.0 stable
- Jaeger exporter peaked at 1.6.0-rc.1 (pre-release); no 1.11.0 exists
- All three services **actively use** Jaeger (Program.cs calls `.AddJaegerExporter()` reading `JAEGER_AGENT_HOST` and `JAEGER_AGENT_PORT`)

### Analysis Findings
1. **Observability is non-negotiable**: Jaeger is a documented feature in `docs/OBSERVABILITY.md` and part of the platform story
2. **All three services are coupled**: expense-api, workflow-engine, notification-svc use identical Jaeger setup
3. **Version was likely aspirational**: 1.11.0 was set across all packages, but Jaeger exporter never shipped that version
4. **Security CVE exists**: OpenTelemetry.Api 1.11.1 has moderate severity; needs investigation post-fix

### Recommendation
**Option A: Downgrade to stable 1.5.1** (recommended over 1.6.0-rc.1 or waiting for 1.11.0)
- ✅ Stable, proven version (no pre-release risk)
- ✅ No code changes required (API compatible with current Program.cs)
- ✅ Unblocks Docker build immediately
- ✅ Allows Phase 7 demo to proceed
- ⚠️ Feature gap vs. 1.11.0 (minor, acceptable for now)

**Rationale:**
- Pre-release (1.6.0-rc.1) adds stability risk in critical observability path
- Waiting for 1.11.0-rc.* has no ETA and blocks demo timeline
- 1.5.1 is production-proven and aligns with Dapr 1.17.5 ecosystem maturity

### Decision Document
Created: `.squad/decisions/inbox/daisy-otel-jaeger-fix-plan.md`
- Comprehensive options analysis (4 options considered)
- Decision factors: backward compatibility, security, observability requirements, service scope
- Team dependencies and success criteria
- Timeline estimate: 3 hours (implementation + security audit + validation)

### Next Steps (for implementation team)
1. Update all three `.csproj` files to `OpenTelemetry.Exporter.Jaeger` 1.5.1
2. Run security audit on OpenTelemetry.Api 1.11.1 CVE
3. Docker build validation
4. Phase 7 end-to-end validation (Jaeger UI traces)
5. Update `docs/OBSERVABILITY.md` with version rationale and future upgrade path

### Architectural Insight
This is a **package ecosystem maturity gap**, not a design flaw. OpenTelemetry is still stabilizing parallel releases across components. The decision to downgrade teaches us:
- Always validate transitive dependency constraints before committing to version numbers
- Pin observable package versions in team wiki (e.g., "Jaeger exporter stable ceiling: 1.5.1 as of April 2026")
- Plan Phase 8 AppInsights integration to move observability to cloud-managed service (Jaeger is local-dev only)

---

## Learnings — Issues #44 & #52

### 2026-07 — Auth Config Portability & API Authentication Docs

**Files touched:**
- `src/expense-api/Program.cs` — removed hardcoded audience fallback, added fail-fast for non-Development
- `src/expense-api/appsettings.json` — added `AzureAd` config section with empty placeholders
- `src/expense-api/appsettings.Development.json` — added dev defaults for Authority/Audience
- `src/ExpenseApi.Tests/OAuth2AuthenticationTests.cs` — fixed 2 tests that incorrectly asserted 401 on anonymous `POST /expenses`
- `docs/API_AUTHENTICATION.md` — created (referenced in code but was missing)
- `README.md` — added link to API Authentication docs

**Decisions:**
- `POST /expenses` is intentionally anonymous (anyone can submit); only approve/reject require auth. Tests and docs now match this design.
- Production fails fast if `AzureAd:Authority` and `AzureAd:Audience` are not configured. Development keeps permissive defaults.
- Used standard ASP.NET `AzureAd__*` env var convention — no custom env var names.
- No `.env.example` file — documented config in `docs/API_AUTHENTICATION.md` instead (the repo has no `.env` workflow).

**Patterns discovered:**
- The subscription ID parameterization was already correct. Scripts use `az account show` for dynamic resolution; Bicep files accept parameters. Issue #44 was already handled at the infrastructure level — the auth audience was the real portability gap.
- `OAuth2AuthenticationTests` had test drift: 2 tests asserted 401 for anonymous POST /expenses, contradicting both the code (`// no authorization required`) and the validation test suite (`ExpenseApiValidationTests`) which called the same endpoint without auth and expected success.

---

## 2026-07 — Blog-Post Readiness Code Review

### Context
Wesley requested a comprehensive code review across all 8 dimensions: architecture, code quality, Dapr patterns, API design, tests, documentation, DevOps, and Kubernetes/Dapr configuration.

### Verdict
**CONDITIONAL** — strong foundation with 6 targeted fixes required before publishing.

### Blocker Summary (6 items)

1. **Dead contracts** — `ExpenseApproved.cs` + `ExpenseRejected.cs` records in `RadiusClaim.Contracts` are never referenced. Unused enum values: `ExpenseSubmitted`, `ApprovalTimeout`, `ExpenseRejectedTimeout`.
2. **Phase metadata in GET /** — `"phase-3"` / `"phase-5"` strings in service descriptors expose internal build scaffolding publicly.
3. **README architecture diagram** — lists `ValidateExpense` activity that doesn't exist. Actual activities: `ApproveExpense`, `ProcessReimbursement`, `PublishNotification`, `RecordApproval`, `RejectExpense`.
4. **Silent exception swallow** — `TryCreateExpenseRecordAsync` has bare `catch when (...){}`. Should log at Warning level.
5. **Inconsistent ConsistencyMode** — expense-api uses `Strong` everywhere; workflow activities use default (eventual). Needs a deliberate decision and comment.
6. **Phase docs in /docs** — `phase-7-*`, `phase7-*` files expose development timeline to external readers.

### Exemplary Patterns (for blog highlighting)
- `ExpenseApprovalWorkflow.cs` — WhenAny race for human-in-the-loop is textbook Dapr workflow
- `RadiusClaimDapr` constants class — centralises all magic strings, eliminates component name drift
- Activity idempotency in `RecordApprovalActivity` and `RejectExpenseActivity`
- `WebApplicationFactory<Program>` + mocked DaprClient testing pattern
- Radius `app.bicep` + recipe separation — infrastructure concern truly isolated from app code


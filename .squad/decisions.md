# Squad Decisions

## Active Decisions

### 2026-03-23: CloudExpense Lite is the reference sample
**By:** Wesley Backelant (captured by Squad)
**What:** Build `CloudExpense Lite`, a small, reference-quality expense filing sample that demonstrates Dapr and Radius together through an employee submit → validate → approve/deny → reimburse → notify flow.
**Why:** The sample needs to be demoable in about ten minutes and understandable to enterprise and platform audiences.

### 2026-03-23: Dapr owns the portable application layer
**By:** Wesley Backelant (captured by Squad)
**What:** Use Dapr building blocks directly in app code — workflows, pub/sub, state, service invocation, and secrets — with optional bindings only where they add clarity.
**Why:** The application story is portability. Dapr is the abstraction that keeps distributed-app logic cloud-agnostic.

### 2026-03-23: Radius owns service and infrastructure wiring
**By:** Wesley Backelant (captured by Squad)
**What:** Use Radius as the primary place to model services, connections, environments, and Azure backing resources. Avoid hand-written Kubernetes YAML as the main deployment path.
**Why:** The platform story is that Radius expresses the environment cleanly while Dapr keeps the app code portable.

### 2026-03-23: Azure is the first target, not an app-code dependency
**By:** Wesley Backelant (captured by Squad)
**What:** Host on Azure Container Apps by preference, but keep application code free of direct Azure SDK calls for messaging, state, and secrets.
**Why:** The sample should be Azure-ready now without giving up portability later.

### 2026-03-23: Squad naming follows 60s-70s blues-rock influence
**By:** Wesley Backelant (via Copilot)
**What:** Use 60s-70s blues and rock influenced names when naming squad members.
**Why:** User request — captured for team memory.

### 2026-03-23: Three-Service Boundary
**By:** Daisy (Lead)
**What:** CloudExpense Lite uses exactly three services: `expense-api`, `workflow-engine`, `notification-svc`.
**Why:** Three services is the minimum to demonstrate service invocation, workflow orchestration, pub/sub fan-out, and state — the four Dapr patterns needed. Fewer would lose the distributed story; more would bloat the demo.

### 2026-03-23: Dapr Workflows as the orchestration model
**By:** Daisy (Lead)
**What:** Use Dapr Workflows (not Durable Functions or custom state machines) for the approval flow.
**Why:** Dapr Workflows are portable across clouds and tie directly into the Dapr story. They also demonstrate checkpoint state naturally.

### 2026-03-23: Azure Container Apps over AKS
**By:** Daisy (Lead)
**What:** Deploy to ACA, not AKS.
**Why:** ACA provides managed Dapr sidecar injection, faster provisioning, and no Kubernetes expertise required. This makes the sample accessible to platform teams who haven't adopted Kubernetes.

### 2026-03-23: Explicit shared contracts in CloudExpense.Contracts namespace
**By:** Daisy (Lead)
**What:** All event and request shapes live in a shared `CloudExpense.Contracts` project as C# records.
**Why:** Prevents drift between services, makes the demo traceable, enables parallel work without merge conflicts.

### 2026-03-23: Auto-approve threshold: Amount < $100.00
**By:** Daisy (Lead), confirmed by Karen (Tester)
**What:** Expenses under $100.00 auto-approve; $100.00 and above enter manual review (not auto-rejected).
**Why:** Clear distinction between terminal rejection and hold-for-review preserves demo credibility and enables multi-tier approval in future phases without schema rewrite.

### 2026-03-23: Tracing model: ExpenseId + CorrelationId
**By:** Daisy (Lead), enforced by Karen (Tester)
**What:** ExpenseId is the stable business identifier; CorrelationId is the end-to-end tracing identifier created at submission and reused by all downstream decisions and notifications.
**Why:** Allows clean tracing from submission → decision → notification without multiplying IDs. Two IDs are the minimum necessary.

### 2026-03-23: UTC timestamp suffixes for all public timestamps
**By:** Daisy (Lead), enforced by Karen (Tester)
**What:** All datetime fields in contracts are explicitly named with `...Utc` suffix (e.g., `SubmittedAtUtc`, `ApprovedAtUtc`).
**Why:** Eliminates timezone ambiguity in demo and future serialization tests.

### 2026-03-23: Distinguish ManualReviewRequested from ExpenseRejected
**By:** Daisy (Lead), enforced by Karen (Tester)
**What:** Amounts >= $100.00 trigger `ManualReviewRequested` event, not rejection. Terminal denials (fraud, compliance) are `ExpenseRejected`.
**Why:** Preserves the distinction between hold and terminal denial, enabling future multi-tier approval without schema rewrite.

### 2026-03-23: Dapr app IDs standardized on service folder names
**By:** Billy (Backend Dev)
**What:** Dapr app IDs are `expense-api`, `workflow-engine`, `notification-svc` (matching folder names, kebab-case).
**Why:** Graham can wire Radius and wiring without reverse-engineering app names. Team gets one place to look for ID definitions.

### 2026-03-23: Phase gating: Phase 1 must complete before Phase 2
**By:** Daisy (Lead)
**What:** Parallel work (Billy app code, Graham platform) authorized only after Phase 1 scaffold passes Karen's validation gate.
**Why:** Prevents merge conflicts, ensures contract stability before implementation diverges.

### 2026-03-23: Phase 5 blocks until local Radius validation
**By:** Daisy (Lead)
**What:** Phase 5 (Azure push) must validate locally first; Phase 5 gate includes local environment test.
**Why:** Prevents deployment surprises; local validation catches Radius and Dapr wiring before Azure provisioning.

### 2026-03-23: Phase 7 blocks until app and platform tracks merge
**By:** Daisy (Lead)
**What:** Phase 7 (docs/tests) starts only after Phase 4+ (app code) and Phase 6+ (platform wiring) are integrated.
**Why:** Tests and docs must cover the full integrated story, not silos.

### 2026-03-23: Phase 1 validation is evidence-based, not test-driven
**By:** Karen (Tester)
**What:** Phase 1 validation uses checklist + fresh build/parse evidence (`dotnet build`, `az bicep build`), not a new test harness.
**Why:** Repo started greenfield; adding a test framework would invent a stack instead of validating the one the team is about to build.

## Phase 1 Exit Criteria (All Passed)

1. ✅ `dotnet build CloudExpense.sln` passes with no errors
2. ✅ Radius `app.bicep` parses: `rad bicep compile infra/app.bicep` succeeds
3. ✅ All four projects reference Contracts
4. ✅ Each service project has a minimal `Program.cs` with `builder.AddDapr()` or equivalent
5. ✅ README.md contains architecture diagram (Mermaid) and service responsibility table
6. ✅ Exact `$100.00` threshold documented in contracts and README
7. ✅ Contracts preserve tracing path (ExpenseId + CorrelationId)
8. ✅ UTC timestamps explicit (all fields suffixed `Utc`)
9. ✅ ManualReviewRequested vs. ExpenseRejected distinct

## Scope Exclusions

The following are **out of scope** for CloudExpense Lite:
- Authentication / authorization
- Real payment processing
- Multiple approval tiers
- Audit logging
- Multi-tenancy

If any of these surface as "nice to have," the answer is no — they muddy the ten-minute demo.

### 2026-03-23: Phase 2 shared index must use optimistic concurrency
**By:** Daisy (Lead)
**What:** Revised `src/expense-api/Program.cs` so `expense-index` is no longer updated with a plain read/modify/write cycle. The recent-expense index now uses Dapr state entry ETags with `FirstWrite` concurrency, strong reads, and bounded retries. Query endpoints now read the record and index paths with strong consistency.
**Why:** Karen correctly found that concurrent submissions could drop IDs from `expense-index`, which made `GET /expenses` untrustworthy. The smallest fix is to harden the shared index key in app code without adding new infrastructure, new endpoints, or Phase 3 workflow behavior.

### 2026-03-23: Phase 2 expense write ordering (Warren — APPROVED)
**By:** Warren
**Artifact:** `src/expense-api/Program.cs`
**Decision:** Persist the expense record before updating the shared recent-expense index. If the index update fails after retries, return a failure response that explicitly says the record was persisted, includes the full record, and provides the fetch location. This is the smallest reviewer-explainable way to avoid phantom index state while keeping the public response truthful about what actually persisted.
**Outcome:** Warren's revision resolves all prior objections. Record-first ordering ensures no phantom entries; strong-consistency re-read on ambiguous saves prevents hidden state; truthful failure disclosure keeps the demo trustworthy. **Phase 2 APPROVED**.

### 2026-03-23: Phase 2 state config — Radius + local Dapr overlay
**By:** Graham (Platform Dev)
**Decision:** Keep Radius authoritative for service topology in `infra/radius/`, and place local-only Dapr component overlays under `infra/dapr/local/`. Billy and local runs use component name `statestore` pointing to `infra/dapr/local/` as the resources path while Redis runs from the colocated compose file.
**Why:** Phase 2 needs a usable Redis-backed `statestore` for local Dapr sidecars, but that should remain a development overlay rather than replacing the Radius-first deployment model.

## Governance

- Keep the sample intentionally small and reference-quality.
- Prefer a few clear endpoints and explicit service contracts over extra features.
- Preserve the separation of concerns: Dapr for app patterns, Radius for platform wiring.
- Use evidence-based validation (fresh builds, fresh parses) before approving phase gates.
- Enforce contract semantics before implementation, not after.

## Phase 2 Exit Criteria (Approved)

Phase 2 write-path deadlock is resolved. The team can proceed to remaining Phase 2 parallel work and Phase 3 planning:
- ✅ Record-first persistence with truthful failure disclosure
- ✅ Optimistic concurrency on shared recent-expense index
- ✅ Strong-consistency verification on ambiguous saves
- ✅ Idempotent replay semantics (matching persisted record → `200 OK`)
- ✅ Demo-trustworthy submit/retrieve story across `POST /expenses`, `GET /expenses/{id}`, `GET /expenses`
- ✅ Local Dapr statestore (Redis) configured under `infra/dapr/local/`

### 2026-03-23: Phase 3 Scope — Dapr Workflows
**By:** Daisy (Lead)
**What:** Implement `ExpenseApprovalWorkflow` with three activities (Approve, Reimburse, Notify), two workflow-engine endpoints, and expense-api fire-and-forget invocation. Cut `ValidateExpenseActivity` (redundant); defer external event wait and notification-svc subscription.
**Why:** Workflows are the one new building block Phase 3 proves. No-op activities confuse the demo without teaching. Fire-and-forget keeps the API contract clean (expense accepted, workflow is async background).

### 2026-03-23: Phase 3 Expense Record as Canonical Source
**By:** Billy (Backend Dev)
**What:** Use the persisted `ExpenseRecord` as the canonical source when `expense-api` invokes `workflow-engine`. Project the stored record back into `ExpenseSubmission` before calling `POST workflow-engine/workflows/start`.
**Why:** If `POST /expenses` generated an `ExpenseId` or `CorrelationId`, forwarding the raw inbound request would break traceability and could start a workflow with ids that don't match persisted state. Using the persisted record keeps `ExpenseId`, `CorrelationId`, workflow instance id, and state transitions aligned.

### 2026-03-23: Phase 3 Pub/Sub as Local Overlay
**By:** Graham (Platform Dev)
**What:** Implement the Phase 3 local Dapr `pubsub` component as a Redis-backed overlay in `infra/dapr/local/pubsub.yaml`, reusing the existing local Redis container on `localhost:6379` and scoping access to `workflow-engine` and `notification-svc` only.
**Why:** Daisy's Phase 3 scope calls for a small, local-only pub/sub slice. Reusing the Phase 2 Redis runtime keeps the change minimal, avoids duplicate emulator infrastructure, and preserves the existing pattern where Radius owns service topology while `infra/dapr/local/` provides development overlays.

### 2026-03-23: Phase 3 Exit Criteria Complete & Approved
**By:** Karen (Tester)
**Status:** APPROVED — 2026-03-23T17:50:00Z
**What:** All 11 exit criteria verified with fresh evidence. Build passes. Workflow and activities registered. Endpoints return correct status codes. Auto-approve path (< $100) produces Submitted → Approved → Reimbursed. Manual review path (>= $100) produces Submitted → ManualReviewRequested. Pub/sub publishes on both paths. Service invocation is fire-and-forget. CorrelationId is the workflow instance ID. pubsub.yaml is correct. No contract changes.
**Why:** Evidence-based validation ensures the implementation matches Daisy's approved scope exactly. State transitions are guarded and idempotent. Failure semantics are truthful. The demo is trustworthy.

## Phase 3 Exit Criteria (Approved)

Phase 3 proves Dapr Workflows orchestrate the expense approval flow with four building blocks: State, Workflows, Pub/Sub, Service Invocation. All 11 exit criteria passed:

- ✅ Build passes: `dotnet build CloudExpenseLite.slnx`
- ✅ Workflow + 3 activities registered in `Program.cs`
- ✅ `POST /workflows/start` returns 202 Accepted
- ✅ `GET /workflows/{instanceId}` returns workflow status or 404
- ✅ Auto-approve path (< $100): Submitted → Approved → Reimbursed
- ✅ Manual review path (>= $100): Submitted → ManualReviewRequested
- ✅ Both paths publish `NotificationRequest` to expense-notifications topic
- ✅ Fire-and-forget service invocation: workflow failure does not block API response
- ✅ `CorrelationId` is the Dapr workflow instance ID
- ✅ `infra/dapr/local/pubsub.yaml` exists, Redis-backed, scoped correctly
- ✅ No contract changes from Phase 2

**Status: Phase 3 APPROVED** — 2026-03-23. All 11 criteria verified. Demo-ready.

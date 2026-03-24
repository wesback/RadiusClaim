# RadiusClaim — Phase 1 Validation Gate

## Why this gate exists

Phase 1 does not need to prove the full submit → approve/deny → reimburse flow yet. It does need to prove the sample can move into behavior work without re-scaffolding contracts, project structure, or platform wiring.

This gate was chosen for a greenfield repository that started without an application scaffold or test harness. Because of that, the right Phase 1 artifact is a **validation checklist plus contract outline**, not a new test stack.

## Current repo readout (2026-03-23)

- The current shell scaffold **does** build with `dotnet build ./RadiusClaim.slnx`.
- Three service shells and a shared contracts project are present.
- The shared contracts implementation is still placeholder-only, so the contract gate is not complete.
- Service project files do not yet show Dapr package references.
- No `infra/app.bicep` file was present during this review, so Graham's side of the Phase 1 gate is still open.

## Validation shape

Phase 1 is acceptable only when these four kinds of evidence are observable:

1. **Scaffold evidence** — the expected solution and project structure exists.
2. **Contract evidence** — shared types support the planned flow and edge cases without platform leakage.
3. **Platform evidence** — the Radius model names the three services and placeholder links cleanly.
4. **Gate evidence** — build and Radius parse results are attached to the change.

## Billy acceptance criteria — scaffold and shared contracts

### 1) Solution and project structure

- A repo-root .NET solution exists and includes the Phase 1 app projects.
- The following directories exist exactly as planned:
  - `src/expense-api/`
  - `src/workflow-engine/`
  - `src/notification-svc/`
- Shared contracts live in one clearly reusable place:
  - dedicated shared project preferred, or
  - shared folder/library if the reuse story is explicit and consistent.
- Each service compiles as a minimal API project with a normal entry point (`Program.cs` or equivalent).
- Dapr package references are present in the service projects where they are needed for the planned flow. Placeholder app logic is fine; missing references are not.

### 2) Build evidence

- `dotnet build` succeeds from the repo root.
- The build output shows there are no missing project references between services and shared contracts.
- A reviewer can identify, from the solution alone, which project owns orchestration and which project owns notifications.

### 3) Shared contract minimums

Contract names can vary slightly if the intent stays intact, but the semantics below must be present.

| Contract | Minimum fields Karen expects | Why it matters |
|---|---|---|
| `ExpenseSubmission` | stable expense identifier, submitter/employee identifier, positive amount, currency, business description, submitted-at UTC timestamp | Supports state lookup, approval logic, and demo narration |
| `ExpenseApproved` | expense identifier, workflow/correlation identifier, approved amount, approved-at UTC timestamp, decision source or approver marker | Keeps the happy path observable |
| `ExpenseRejected` | expense identifier, workflow/correlation identifier, rejected-at UTC timestamp, human-readable reason | Keeps the failure path explainable |
| `NotificationRequest` | expense identifier, verdict/event type, recipient target, message or template payload, occurred-at UTC timestamp | Lets notification behavior be validated later without rewriting the contract |

### 4) Contract quality rules

- Public contracts stay **cloud-agnostic**:
  - no Azure SDK types
  - no Azure resource identifiers as required payload fields
  - no Dapr runtime types in the public message shape
- Amount values use decimal-money semantics, not floating-point approximations.
- Timestamps are UTC and explicitly named that way.
- Correlation between submission, workflow, and notification is possible from identifiers alone.
- A rejection/denial cannot exist without a reason field.

### 5) Threshold and validation edge criteria

These must be answered in Phase 1 so Phase 2 does not smuggle in behavior changes:

- Negative or zero amounts are invalid input, not approval outcomes.
- The exact **`$100.00` boundary must be documented explicitly**. The plan says “auto-approve `< $100`” and “flag `> $100`”; that leaves `= $100` ambiguous.
- If Billy keeps only approved/rejected event contracts in Phase 1, the change must still document how a “manual review / not auto-approved” path will be represented later.
- Contract shape must preserve enough information for a reviewer to distinguish:
  - invalid submission
  - approved expense
  - denied/rejected expense
  - needs-human-decision path, if introduced later

## Graham acceptance criteria — Radius scaffold

- An `app.bicep` skeleton exists in the expected repo location.
- The model declares the three planned service/container identities clearly:
  - `expense-api`
  - `workflow-engine`
  - `notification-svc`
- Placeholder links exist for the three platform capabilities the sample depends on:
  - state
  - pub/sub
  - secrets
- Link names describe capability, not implementation detail, so the app model stays portable.
- The Radius model does not make Kubernetes YAML the primary deployment path.
- The change includes evidence of a clean Radius parse/validation run, with the exact command used recorded in the PR or change notes.

## Lightweight Phase 1 contract test outline

No new harness is introduced here. This is the minimum outline Karen will expect Billy to turn into executable tests once the .NET test stack exists in-repo.

### Contract checks to automate next

1. **Build contract ownership**
   - Services reference shared contracts without duplication.
2. **Serialization safety**
   - Each shared contract can be serialized/deserialized without dropping identifiers, verdict, amount, or timestamps.
3. **Boundary examples**
   - Submission below threshold
   - Submission at exactly `$100.00`
   - Submission above threshold
   - Submission with invalid amount
   - Rejection payload with required reason
   - Notification payload carrying the final verdict

## Reviewer verdict guide

- **Pass** — all checklist items are observable, build passes, Radius parses, and the threshold ambiguity is resolved or explicitly documented.
- **Conditional pass** — structure/build is correct, but one non-blocking documentation gap remains and is captured in the PR.
- **Reject** — missing shared contract location, ambiguous threshold behavior, no build evidence, or no Radius parse evidence.

## Minimum evidence package for a Phase 1 PR

- repo tree snippet or screenshot showing the service and shared-contract structure
- `dotnet build` success output
- Radius parse/validation success output
- short note explaining the exact `$100.00` behavior decision

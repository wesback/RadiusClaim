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

## Governance

- Keep the sample intentionally small and reference-quality.
- Prefer a few clear endpoints and explicit service contracts over extra features.
- Preserve the separation of concerns: Dapr for app patterns, Radius for platform wiring.
- Use evidence-based validation (fresh builds, fresh parses) before approving phase gates.
- Enforce contract semantics before implementation, not after.

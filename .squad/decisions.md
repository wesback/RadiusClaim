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

## Governance

- Keep the sample intentionally small and reference-quality.
- Prefer a few clear endpoints and explicit service contracts over extra features.
- Preserve the separation of concerns: Dapr for app patterns, Radius for platform wiring.

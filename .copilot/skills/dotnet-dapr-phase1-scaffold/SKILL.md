---
name: "dotnet-dapr-phase1-scaffold"
description: "Scaffold a small .NET + Dapr service set with shared contracts and explicit integration constants"
domain: "backend-scaffolding"
confidence: "high"
source: "earned"
---

## Context

Use this when a repo needs the first backend slice of a Dapr-based sample without jumping ahead into business logic. The goal is to leave behind buildable services, shared contracts, and visible service/topic names.

## Patterns

### Solution layout
- Create one repo-level solution and pin the SDK with `global.json`.
- Put runnable services in descriptive folders such as `src/expense-api`, `src/workflow-engine`, and `src/notification-svc`.
- Put shared payloads in a separate class library such as `src/shared/RadiusClaim.Contracts`.

### Dapr setup
- Add `Dapr.AspNetCore` to web hosts that will participate in invocation or pub/sub.
- Add `Dapr.Workflow` only to the orchestration host.
- Register `AddDaprClient()` in each service so later phases can inject Dapr clients without reshaping startup.
- Use `UseCloudEvents()` everywhere that may handle Dapr events; add `MapSubscribeHandler()` on subscriber services.

### Contract design
- Favor one file per request/event shape.
- Keep payloads explicit and demo-friendly: IDs, actors, money, timestamps, and reasons should be present in the contracts rather than inferred.
- For workflow-driven demos, keep two identifiers only: a stable business ID (for the record) and a correlation ID (for end-to-end tracing). Reuse the correlation ID as the workflow instance ID later instead of inventing a third identifier early.
- Suffix public timestamps with `Utc` and reserve rejection contracts for terminal denials; use a separate event type for future manual-review holds.
- Centralize Dapr-facing constants for app IDs, component names, workflow names, and topic names in the contracts assembly.

## Examples

```csharp
builder.Services.AddDaprClient();
app.UseCloudEvents();
app.MapSubscribeHandler();

public sealed record ExpenseApproved(
    string ExpenseId,
    string CorrelationId,
    string EmployeeId,
    decimal ApprovedAmount,
    string Currency,
    string DecisionSource,
    DateTimeOffset ApprovedAtUtc);
```

## Anti-Patterns

- Hiding app IDs and topic names as repeated string literals across services.
- Mixing Phase 1 scaffolding with Phase 2+ business logic.
- Sharing payloads by copy/paste instead of a contracts project.

---
name: "phase-7-gate"
description: "Pattern for final lead review of Phase 7 deliverables: documentation, demo walkthrough, validation tooling"
domain: "phase-gates"
confidence: "high"
source: "daisy-phase7"
---

## Context

Use this when conducting a **final lead review of Phase 7 deliverables** (documentation, 
demo walkthrough, validation scripts, GitHub Actions configuration). Phase 7 is the 
finalization lane; all app code and platform wiring are complete. This gate validates 
that the sample is demo-ready and the story is externally credible.

## Review Framework

### 1. Truthfulness-First Assessment

Before any structural check, audit for truth violations:

- **Threshold accuracy:** If the sample claims "$100 boundary auto-approve," does the 
  code actually enforce it? Check contracts, validation script, and demo walkthrough.
- **Portability claims:** If the sample claims "same app code runs anywhere," verify 
  zero cloud-specific SDK dependencies.
- **Tool ownership:** If the sample claims "Radius owns deployment," verify the 
  deployment path actually uses `rad deploy`. If it bypasses Radius (e.g., `az containerapp`), 
  either fix the path or openly document the gap.
- **Demo narrative:** Does the story arc require CorrelationId traceability? If yes, 
  verify it's designed in and flows end-to-end.

### 2. Scope Boundary Discipline

Phase 7 is **finalization only**. Flag any of these as out-of-scope scope creep:

- **App code changes:** App is done. Documentation and validation only.
- **Infrastructure redesign:** Platform wiring is settled. No new architecture.
- **Feature additions:** Demo scope is fixed ($100 threshold, two flows). No new endpoints.
- **Tool additions:** Use existing validation (dotnet build, bicep build, shell script). 
  Don't invent new test frameworks.

### 3. External Demo Credibility

Judge all artifacts as if you were presenting to a platform team:

- **Can I run the demo in ~10 minutes?** Check timeline in walkthrough.
- **Can I see proof the system works end-to-end?** Check: does validation script check 
  state persistence, workflow orchestration, service invocation, and CorrelationId flow?
- **Do I understand why this is built the way it is?** Check: does the README and ADR 
  explain architectural choices and tradeoffs?
- **Is the sample honest about limitations?** Check: ACA fallback labeled as gap? 
  Real notifications deferred? Multi-cloud explicitly out-of-scope?

## Patterns

### Truth-Critical Checklist

1. **Build & Parse:** Run `dotnet build` and `az bicep build`. Zero errors, zero warnings.
2. **Threshold Logic:** Verify $100 boundary in three places: contracts, validation script, 
   demo walkthrough. All must agree.
3. **Dapr Component Names:** Verify component names stable across app code, Radius models, 
   local overlays, and validation script.
4. **Demo Narrative:** Trace CorrelationId from submission curl → API response → workflow 
   state → notification logs. All must carry the same ID.
5. **Radius vs ACA:** If both paths exist, verify one is labeled primary and one is 
   labeled fallback. Primary must be primary in code (default in CI/CD), not just 
   documentation.

## Escape Hatch Pattern for Environment Dependencies

When Phase 7 requires an external dependency (live Radius environment) that may not be available:

1. Document the gap explicitly in validation checklists
2. Provide structural validation (Bicep parse, pod health) as sufficient for closure
3. Commit to end-to-end validation within 2 weeks of environment availability
4. This prevents gates from hanging indefinitely

## References

- **Phase 7 Final Review Decision:** `.squad/decisions/inbox/daisy-phase7-final-review.md`
- **Phase Gate Validation Skill:** `.squad/skills/phase-gate-validation/SKILL.md`

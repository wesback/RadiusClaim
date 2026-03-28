---
timestamp: 2026-03-25T11:05:39Z
topic: pubsub-deploy-triage
severity: BLOCKING
---

# Session Log: Pubsub Deployment Triage (2026-03-25)

## Issue Summary

Live `rad deploy` failure: pubsub resource enters FAILED state, blocking expense-api-service and expense-api modules in indefinite in-progress loop.

## Diagnosis Model (Daisy + Graham)

**Daisy identified:** Failed dependency deadlock. When pubsub fails, downstream modules cannot resolve `pubsub.id` → Radius orchestrator enters unresolvable wait loop.

**Graham isolated:** Three-layer diagnosis:
1. expense-api lacks pubsub connection (low-impact design gap, likely intentional)
2. Recipe contract drift between pubsub.bicep output and Dapr metadata (medium-impact, version skew signal)
3. Implicit deployment ordering: pubsub failure blocks downstream services via unresolvable reference chain (critical root cause)

## Root Cause

**Pubsub recipe deployment fails** → recipe output (namespace FQDN + connection string) never materializes → services attempting to connect remain indefinitely in-progress → Radius orchestrator cannot evaluate downstream module connections because upstream reference unresolvable.

## Immediate Actions

1. Verify Service Bus namespace provisioning: `az servicebus namespace list`
2. Check Radius logs for pubsub resource error: `rad resource logs pubsub --application radiusclaim`
3. Validate recipe Bicep compiles: `az bicep build --file infra/radius/recipes/azure/pubsub.bicep`
4. Deploy pubsub in isolation (skip service modules) to isolate failure domain

## Decision

**BLOCKING Phase 7 validation** until Graham verifies pubsub recipe health and confirms execution succeeds in isolation.

**Architectural Lesson:** Single failed recipe can block entire application deployment. Pre-deployment recipe validation (compilation + type checking) must be CI gate before `rad deploy`.

---

**Status:** Awaiting Graham's pubsub recipe health verification and isolated deployment test.

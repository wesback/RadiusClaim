# Decision: Operator Docs Updated for Component Projection Gap and Two-Path Structure

**By:** Eddie (Docs/Story)
**Date:** 2026-03-25
**Status:** IMPLEMENTED

## What Changed

### 1. Component Projection Gap Documented
All operator docs now acknowledge the Radius component projection gap: `Applications.Dapr/*` resources may report Succeeded without actually projecting `components.dapr.io` CRDs to Kubernetes. This is now documented as **Step 9a** in the walkthrough and **Step 5a** in the checklist, both pointing to `scripts/deploy-dapr-components.sh`.

### 2. Namespace Misuse Fixed Across All Docs
All `kubectl` commands for pods, logs, components, port-forwards, and pull secrets now use `$WORKLOAD_NAMESPACE` (`radiusclaim-azure-radiusclaim`), not the environment namespace (`radiusclaim-azure`). The checklist adds a "Understanding Namespace Roles" section with explicit variable definitions early.

### 3. Two Deployment Paths Framed
The walkthrough now opens with a table distinguishing:
- **Manual walkthrough** (Steps 1–12) for learning
- **Bootstrap script** (`scripts/bootstrap.sh`, when available) for returning operators

The bootstrap script doesn't exist yet. The docs are structured so it can be wired in without rewriting the walkthrough.

### 4. Pull Secret Block Fixed
The checklist's pull-secret troubleshooting now patches named service accounts (`expense-api`, `workflow-engine`, `notification-svc`), not `default`. Patching `default` has no effect because Radius creates dedicated service accounts for each container resource.

### 5. README Stale References Fixed
- `sovereignapp/` → `RadiusClaim/` in project layout
- Added `scripts/` tree to project layout
- Added component backfill paragraph to deployment story

### 6. scripts/README.md Updated
Added full documentation for `deploy-dapr-components.sh` with usage, options, examples, and prerequisites.

## Why This Matters

The previous docs would have led operators to:
- Check for components in the wrong namespace (100% failure)
- Skip the backfill step entirely (services crash at runtime)
- Patch the wrong service accounts for pull secrets (no effect)

These were not edge cases — they were the default path through the documentation.

## Team Impact

- **Graham:** If the bootstrap script lands, wire it into the walkthrough's "Two Paths" table.
- **Karen:** Validation script namespace in `scripts/README.md` (`-n radiusclaim-azure`) may need updating to `$WORKLOAD_NAMESPACE` for the port-forward example there.
- **Daisy:** The walkthrough's Step 9a is designed to absorb CI integration cleanly — the backfill script already supports `--dry-run` and auto-detection.

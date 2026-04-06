# RadiusClaim Test Scripts — Quick Reference

## Overview

Five diagnostic scripts verify RadiusClaim deployment layer-by-layer. Run them in order to isolate issues.

| # | Script | What It Tests | Fails When |
|---|--------|---------------|-----------|
| 1 | `health-check.sh` | Cluster, pods, components exist | Pods not Running, components missing |
| 2 | `api-endpoint-test.sh` | HTTP endpoints respond | API crash, port mismatch, networking |
| 3 | `dapr-component-test.sh` | State store & pub/sub work | Azure RBAC, Dapr sidecar issues |
| 4 | `expense-submit-test.sh` | Complete submission flow | POST handler, state write, counter |
| 5 | `workflow-trigger-test.sh` | Workflows process events | Pub/sub wiring, workflow subscription |

## Quick Start

```bash
# Run all tests
./scripts/deployment-readiness.sh

# Run individual test
./scripts/health-check.sh
```

## Output Files

- **TEST_CHECKLIST.md** — Tick-off checklist with expected results and failure recovery steps
- **SCRIPT_REVIEW.md** — Detailed review of all scripts, bugs fixed, and quality metrics
- **README_TESTS.md** — This file (quick reference)

## Test Results Interpretation

### ✅ All Green
Infrastructure is ready. If app still doesn't work, check:
- API code logic (recent changes?)
- Authentication/authorization
- Environment variables & secrets
- UI making correct API calls

### ❌ One Test Failed
Use the flowchart in TEST_CHECKLIST.md to determine next steps.

Example: If Test 3 (Dapr components) fails:
1. Check Azure Storage RBAC
2. Verify Service Bus credentials
3. Restart Dapr components

## Most Common Issues

1. **"Can't set state"** → Missing Storage Blob Data Contributor role
2. **"API returns 500"** → Check `kubectl logs <pod> -n radiusclaim-azure-radiusclaim`
3. **"Workflow doesn't process event"** → Restart pod: `kubectl rollout restart deployment/workflow-engine`
4. **"Counter not incrementing"** → Check if POST handler increments in source code

## Files Modified During Review

✅ `scripts/api-endpoint-test.sh` — Fixed port label, 401/403 handling
✅ `scripts/dapr-component-test.sh` — Removed set -e for robustness
✅ `scripts/workflow-trigger-test.sh` — Removed set -e for robustness
✅ `scripts/health-check.sh` — No changes (production-ready)
✅ `scripts/expense-submit-test.sh` — No changes (production-ready)
✅ `scripts/deployment-readiness.sh` — No changes (production-ready)

## Getting Help

When stuck:
1. Run the test that failed with full output
2. Note which specific check failed
3. Use diagnostic commands in TEST_CHECKLIST.md
4. Check pod logs: `kubectl logs <pod> -n radiusclaim-azure-radiusclaim`


# Orchestration Log — Pete Scripts Audit → Merge

**Date:** 2026-03-27  
**Time:** 09:05:00Z  
**Agent:** Pete (Infrastructure Automation Specialist)  
**Scribe:** Scribe  
**Event:** Scripts audit findings → inbox merge + orchestration record

---

## Audit Results

Pete completed a comprehensive read-only audit of all `scripts/` files. Found **2 critical issues**, 4 consistency issues, 2 quality issues, 1 idempotency note.

### Critical Findings

1. **bootstrap.sh calls deprecated deploy-dapr-components.sh**
   - Line 960 invokes the old service-principal version instead of the workload-identity version
   - Operators must manually run `deploy-dapr-components-workload-identity.sh` after bootstrap finishes
   - Undocumented post-bootstrap step breaks automation chain

2. **teardown.sh never deletes managed identity radiusclaim-workload-identity**
   - Identity created by `deploy-dapr-components-workload-identity.sh` accumulates across setup/teardown cycles
   - Resource orphaning risk; cleanup must be manual

### Secondary Issues (6 items)

- Flag naming inconsistency: `--workspace-name` vs `--workspace` between scripts
- teardown.sh missing `--group-name` flag (bootstrap/prepare-cluster have it)
- GHCR owner/repo hardcoded in teardown.sh delete_ghcr_artifacts() function
- Both deploy-dapr scripts don't use team logging functions (fail, log_info, log_success)
- deploy-dapr-components-workload-identity.sh header comment names wrong script
- bootstrap.sh DRY_RUN style inconsistency (`if "$DRY_RUN"` vs `[ "$DRY_RUN" = true ]`)
- publish-radius-recipes.sh auth detection is ineffective
- README doesn't mark deploy-dapr-components.sh as deprecated
- bootstrap.sh SHOULD_REGISTER_AZURE_CREDENTIAL re-registration is silent (correct but non-obvious)

---

## Scribe Actions

✅ **Task 1: Orchestration Log** → This file  
✅ **Task 2: Session Log** → `.squad/log/2026-03-27T09-05-00Z-pete-audit-complete.md`  
✅ **Task 3: Decision Inbox Merge** → `.squad/decisions/inbox/pete-scripts-audit.md` merged into `.squad/decisions/decisions.md`, inbox file deleted  
✅ **Task 4: Pete's History** → Appended findings + recommended actions to `.squad/agents/pete/history.md` under Learnings  
✅ **Task 5: Git Commit** → staged `.squad/` + `scripts/teardown.sh`, committed with fix message

---

## Outcome

Audit findings documented, inbox merged, team decision registry updated, Pete's learning history advanced. teardown.sh pre-flight checks (Azure CLI login + SPN lookup timeout) staged for commit.

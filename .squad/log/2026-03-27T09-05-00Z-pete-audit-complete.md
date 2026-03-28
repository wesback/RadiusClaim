# Session Log — Pete Scripts Audit Completion

**Date:** 2026-03-27  
**Time:** 09:05:00Z  
**Agent:** Pete → Scribe  
**Summary:** Full scripts audit → critical findings documented, inbox merged, team records updated

---

## Findings Summary

Pete audited all `scripts/` files and identified:

### 🔴 Critical Issues (2)

1. **bootstrap.sh line 960 calls deprecated deploy-dapr-components.sh**
   - Impact: Automated bootstrap never sets up managed identity, federated credentials, WI labels, or WI-based Dapr manifests
   - Fix: Call `deploy-dapr-components-workload-identity.sh` with `--cluster-name`

2. **teardown.sh does not delete managed identity `radiusclaim-workload-identity`**
   - Impact: Identity and federated credentials accumulate across setup/teardown cycles
   - Fix: Add managed identity deletion (gated by flag) or warn with resource name if skipped

### Secondary Issues (6)

- Flag naming: `--workspace-name` vs `--workspace` inconsistency across scripts
- teardown.sh missing `--group-name` flag (breaks custom group cleanup)
- GHCR hardcoded in teardown.sh (wrong on forks)
- deploy-dapr scripts missing team logging functions (raw echo + exit instead of fail/log_info/log_success)
- deploy-dapr-components-workload-identity.sh header names wrong script
- bootstrap.sh DRY_RUN style inconsistency (`if "$DRY_RUN"` vs bracket form)
- publish-radius-recipes.sh auth detection ineffective (always falls through to warning)
- README missing deprecation notice for deploy-dapr-components.sh
- bootstrap.sh AZURE_CREDENTIAL re-registration is silent (behavior correct, signal missing)

---

## Scribe Handoff

✅ Orchestration log created  
✅ Inbox decision merged into decisions.md  
✅ Pete's history updated with learnings  
✅ Git commit staged (teardown.sh + .squad/)

**Next:** Team review teardown.sh changes and decide bootstrap.sh refactor scope.

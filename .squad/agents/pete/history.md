---
last_updated: 2026-05-05T08:58:18Z
status: archived_2026-05-05
---

# Pete History (Summarized)

**Role:** Infrastructure Automation Specialist — scripts, bootstrapping, Azure automation, role assignments.

## Key Learnings & Fixes

### Bash Argument Parsing Best Practice
- **Pattern:** Always handle both `--flag VALUE` and `--flag=VALUE` forms in argument parsers
- **Example fix:** Added both `--cluster-name)` and `--cluster-name=*)` cases in `scripts/bootstrap.sh`
- **Applied to:** All scripts with value-taking flags

### Bootstrap SPN Role Assignment Idempotency (2026-06-05)
- Fixed reuse path: when existing SPN is reused, script must verify Contributor role is assigned
- Implementation: `az role assignment create` (suppress "already exists" errors) + verify with `az role assignment list`
- Both create and reuse paths now guarantee SPN has Contributor before proceeding

### Script Audit Remediation (2026-06-05)
- Fixed 8 audit findings in scripts: bootstrap, teardown, publish, deploy-dapr
- All critical/high priority fixes applied (wrong Dapr script, missing identity cleanup, flag inconsistencies, hardcoded values, missing lib sourcing)
- All scripts pass `bash -n` syntax check

### GHCR Package Deletion Fix
- Fixed forward slash encoding in GitHub API calls: `/radiusclaim/expense-api` → `radiusclaim%2Fexpense-api`
- Updated URL encoding to handle multi-level package names

## Current Status

All infrastructure scripts audit-compliant and idempotent. Bootstrap automation handles SPN creation and role assignment robustly.

---

## Shell Script Cleanup Implementation (2026-05-05, Session T11:34Z)

**Task:** Remove debug shell scripts and log artifacts per Daisy's classification.  
**Outcome:** ✓ Removed 7 debug scripts + 11 log files; all supported scripts preserved.  
**Scripts Removed:** analyze_critical.sh, deep_conflict_check.sh, final_analysis.sh, final_strategy.sh, merge_analysis.sh, merge_strategy.sh, squad_changes_detail.sh  
**Logs Removed:** All bootstrap/teardown run artifacts from April 3 testing  
**Verification:** No references in README, TEST_GUIDE, or workflows; .gitignore already covers `*.log`; all supported operational scripts intact.  
**Impact:** Repository surface cleaner; zero impact to supported workflows. Daisy alignment boundaries honored throughout.

**Full history archived to `.squad/agents/pete/history-archive.md`**

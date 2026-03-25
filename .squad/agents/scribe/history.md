# Project Context

- **Owner:** Wesley Backelant
- **Project:** CloudExpense Lite — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Learnings

- Seeded into the repo for a Dapr + Radius reference sample named `CloudExpense Lite`.
- The sample must stay intentionally small, demoable in roughly ten minutes, and aimed at enterprise/platform audiences.
- Azure is the current target, but application code must stay cloud-agnostic through Dapr abstractions.
- Track the staffed squad, the user's naming preference, and the CloudExpense Lite brief as the starting memory set.

## Build Output Cleanup (2026-03-24)

**Decision:** After the CloudExpense → RadiusClaim rename commits, restored 345 tracked build files to HEAD state and removed 24 untracked build artifacts from the working tree. The two rename commits (be860d1, 3241402) remain intact with all source code changes preserved.

**Action taken:**
- Restored tracked build outputs (bin/, obj/ for all services and contracts) to match HEAD via `git checkout HEAD`
- Removed untracked generated files (RadiusClaim.Contracts DLLs, static web assets, cache files) via `git clean -fd`
- Verified: 345 tracked build files remain as expected, showing legitimate differences from HEAD due to post-rename build validation
- Remaining source-level changes: `README.md`, `docs/radius-validation-checklist.md`, `.squad/agents/eddie/history.md` (3 files outside build/ directories)

**Outcome:** Git working tree is now clean of untracked build churn. All rename work preserved. Tracked build outputs reflect current compilation state after project rename validation.

## 2026-03-24: Orchestration Log Entry for Eddie Agent

**Task:** Process Eddie (Docs/Story) agent work and scribe records.

**Actions:**
- ✅ Created orchestration log: `.squad/orchestration-log/2026-03-24T16:17:51Z-eddie.md`
- ✅ Created session log: `.squad/log/2026-03-24T16:17:51Z-walkthrough-location.md`
- ✅ Merged inbox decision to `.squad/decisions.md` (deduped)
- ✅ Updated Eddie's `.squad/agents/eddie/history.md` with work summary
- ✅ Prepared git commit

**Outcome:** ✅ Scribe records complete. Team logs documented.


---

## 2026-03-24T17:53:40Z: Orchestration & Decision Merge Session

**Work:** Consolidated pending inbox decisions (2 files), created orchestration + session logs for Graham's Daisy follow-ups, cleaned inbox.

**Files Written:**
- `.squad/orchestration-log/2026-03-24T175340Z-graham.md` — Graham's follow-up implementation orchestration
- `.squad/log/2026-03-24T175340Z-daisy-followups.md` — Session handoff summary
- `.squad/decisions/decisions.md` — Updated with Decisions 6–7 (Graham C2/C3/C7 + Karen approval)

**Inbox Purged:** graham-daisy-followups.md, karen-radius-compute-review.md removed.

**Decisions Registry Status:** 7 active decisions, updated 2026-03-24T17:53:40Z.

**Agents Updated:** Graham, Daisy, Karen history files appended with follow-up orchestration work.

---

## 2026-03-25T10:17:49Z: GHCR Private-by-Default Documentation Audit & Decision Merge

**Work:** Process Eddie audit outcome and Graham recovery reference; merge 4 inbox decisions into main registry; delete inbox files; update agents' history.

**Files Written:**
- `.squad/orchestration-log/2026-03-25T10-17-49Z-eddie.md` — Eddie's GHCR audit and recommended doc changes
- `.squad/log/2026-03-25T10-17-49Z-ghcr-private-doc-audit.md` — Session summary for audit work
- Updated `.squad/decisions/decisions.md` — Added Decisions 11 (Eddie GHCR docs) and 12 (Graham recovery reference)

**Inbox Purged:** eddie-ghcr-private-docs.md, eddie-docs-review.md, graham-recovery-commands.md, graham-sovereignapp-pubsub-diagnosis.md removed.

**Decisions Registry Status:** 12 active decisions, updated 2026-03-25T10:17:49Z. Decisions 11–12 focus on GHCR private-by-default documentation clarity (Eddie audit) and live cluster recovery reference (Graham platform guidance).

**Deduplication:** Verified no duplicate problem statements across merged entries. Graham's recovery reference complements Eddie's doc audit—both address GHCR 403 blocker from different angles (preventive docs vs. operational playbook).

**Outcome:** Inbox merged, orchestration/session logs documented, team decision registry current.

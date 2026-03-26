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

---

## 2026-03-25T11:31:49Z: Namespace Guidance Docs Fix — Orchestration & Decision Merge

**Work:** Process Eddie (Docs/Story) namespace clarification work; merge 3 inbox decisions into main registry; delete inbox files; update affected agents' history.

**Files Written:**
- `.squad/orchestration-log/2026-03-25T11-31-49Z-eddie.md` — Eddie's namespace guidance orchestration record
- `.squad/log/2026-03-25T11-31-49Z-namespace-docs-fix.md` — Brief session summary for namespace docs fix
- Updated `.squad/decisions/decisions.md` — Consolidated Decisions 1–5 from archived registry + merged 3 inbox decisions (namespace guidance, AKS docker_bridge_cidr resolution, README sample disclaimer)

**Inbox Purged:** eddie-namespace-guidance.md, eddie-aks-network-warning.md, eddie-readme-sample-disclaimer.md removed.

**Decisions Registry Status:** 5 active decisions, updated 2026-03-25T11:31:49Z. Decisions focus on:
1. Full codebase audit findings (Daisy)
2. Namespace discovery pattern (Eddie) — removed misleading fallback, added transparent kubectl discovery workflow
3. AKS docker_bridge_cidr SDK compatibility (Eddie) — resolved, no action needed for RadiusClaim
4. README sample code disclaimer (Eddie) — placement between intro tagline and problem statement
5. Live cluster recovery commands (Graham) — operational reference for image pull failures

**Deduplication:** Verified no overlaps across merged entries. All three Eddie decisions addressed distinct concerns (namespace config transparency, SDK compatibility note, README messaging).

**Agents Updated:** Eddie history appended with namespace discovery learning. Scribe history (this file) documents full orchestration cycle.

**Outcome:** Inbox merged, orchestration/session logs documented, team decision registry current. Namespace guidance decision fully integrated into project memory.
## 2026-03-26: Orchestration & Decision Merge — Statestore Diagnosis

**Work:** Logged Graham's live statestore diagnosis, created the orchestration and session records, merged three inbox decisions into `.squad/decisions.md`, and cleared the inbox.

**Files Written:**
- `.squad/orchestration-log/2026-03-26T13-57-17Z-graham.md`
- `.squad/log/2026-03-26T13-57-17Z-radius-statestore-diagnosis.md`
- Updated `.squad/decisions.md` — added statestore diagnosis and consolidated GHCR auth/validation

**Inbox Purged:** `graham-ghcr-recipe-auth.md`, `graham-statestore-diagnosis.md`, `karen-ghcr-publish-validation.md`

**Outcome:** Scribe records updated; team decision registry current.

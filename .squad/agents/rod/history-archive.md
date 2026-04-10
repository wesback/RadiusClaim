# Rod — History & Learnings

## Project Context

- **Owner:** Wesley Backelant
- **Project:** RadiusClaim — Dapr + Radius reference sample
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Kubernetes-first Azure-backed platform wiring
- **Description:** A small, reference-quality expense filing sample that demonstrates portable app patterns with Dapr in the app layer and Radius in the platform layer.
- **Joined:** 2026-04-01


---

## Core Context — Archived Learnings

The following sessions (prior to 2026-04-01) established foundational understanding:

- **Radius CLI Idempotency** — Confirmed `rad app delete` pattern, two-arg split for `rad resource delete`
- **Radius Namespace Migration** — Deprecation warnings are cosmetic; migration deferred until Radius ships `Radius.Core/*`
- **Bootstrap Idempotency Guards** — Environment-level and application-level guards added via `.squad/skills/radius-idempotent-deployment/`
- **Dapr Component Stale Environment Binding** — Pre-deploy cleanup guards; environment binding detection via `rad resource list` JSON `.properties.environment`
- **Radius Database Orphaned References** — Direct `kubectl delete` bypasses Radius control plane; orphaned state requires reinstall
- **Radius Reinstall Recovery** — `rad uninstall kubernetes` → `rad install kubernetes` → recreate workspace/group/environment

These learnings informed the script drift fixes and async deletion verification patterns.
For detailed context, see turn history in Scribe logs or session records.

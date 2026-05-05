# Rod — History Summary

**Generated:** 2026-04-11T11:59:20Z

## Overview
- Total history entries: 8
- Date range: 2026-04-01 to 2026-04-11
- File was archived due to size (>15KB)

## Recent Activity
See history-archive.md for full timeline.

## Learnings

- 2026-06-06 — The deployable app model in this repo is still `Applications.Core/*` + `Applications.Dapr/*` on `2023-10-01-preview`; the app-modeling skill references `Radius.*` preview types, so generated Bicep must be reviewed against the live repo model before use.
- 2026-06-06 — `bootstrap.sh` duplicates Azure recipe naming logic for Key Vault preflight and currently diverges from `infra/radius/recipes/azure/secrets.bicep`; preflight name prediction must share the same formula as the recipe or it silently stops protecting idempotent redeploys.
- 2026-06-06 — Radius environment recipe contracts need hard verification: `dev.bicep` omits required Azure recipe parameters, and bootstrap’s per-run random suffixing defeats in-place idempotent updates by creating fresh backing resources each deploy.

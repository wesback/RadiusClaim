# Session Log: GHCR ImagePullBackOff Deployment Fix (2026-03-28T09:39:21Z)

## Session Summary
Parallel investigation and root cause analysis of `ImagePullBackOff` / `401 Unauthorized` failures across all deployment targets (local Radius, CI-to-AKS, fresh clusters).

## Agents Engaged
- **Daisy** (Lead) — Deep dive root cause analysis, issue creation, decision leadership
- **Graham** (Platform Dev) — Radius Bicep wiring validation
- **Pete** (Infra Automation) — CI/CD and scripts gap analysis

## Key Findings

1. **Design:** ✅ Infrastructure plumbing is complete and correct
   - `app.bicep` → `container-service.bicep` wiring is sound
   - `imagePullSecrets` parameter flows correctly to pod spec

2. **Operations:** ❌ Two operational gaps identified
   - CI workflow (`deploy-azure.yml`) missing pull secret creation and parameter
   - No local developer build/push script exists

3. **Root Cause:** GHCR packages (`ghcr.io/wesback/radiusclaim/*`) are private
   - Source code is public, but container images are private by default
   - Pods attempt anonymous pull → 401 Unauthorized → ImagePullBackOff

## Decision Adopted
**GHCR Auth Strategy — Public Packages for Public Repo** (daisy-ghcr-auth-strategy.md)
- Make all service image packages public
- Reason: Teachability (no auth ceremony for demos), consistency with public recipe packages
- Fallback: imagePullSecrets infrastructure remains for private forks

## Issues Created
- #33 — Make GHCR packages public (P0, immediate)
- #34 — Fix CI workflow pull secret gap (P1)
- #35 — Local dev build-and-push script (P1)
- #36 — Conditional pull secret logic in bootstrap.sh (P2, cleanup)

## Next Steps
- Daisy to drive issue #33 (making packages public) as immediate fix
- Pete to implement issue #35 (local script) and #34 (CI workflow fix)
- Graham to validate Radius deployment once fixes applied

## Time Estimate to Resolution
- Make packages public: ~5 min per package (3 packages = 15 min)
- CI workflow fix: ~30 min (test in PR)
- Local script: ~1 hour (script creation + documentation)

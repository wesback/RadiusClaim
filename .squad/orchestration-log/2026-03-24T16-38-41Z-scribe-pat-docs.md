# Orchestration Log: PAT Documentation Update

**Timestamp:** 2026-03-24T16:38:41Z  
**Agent:** Scribe  
**Spawn:** Eddie (Docs/Story Agent)

## Summary
Eddie updated `docs/end-to-end-setup-walkthrough.md` to add GitHub Personal Access Token (PAT) creation guidance near the GHCR authentication flow. Also removed deprecated `--wait` flag from Radius install command.

## Changes Captured
1. **New PAT Section:** Step 6 now includes "Create a GitHub Personal Access Token (PAT)" subsection with:
   - Fine-grained PAT instructions (not classic)
   - Least-privilege scopes: `write:packages` (push to GHCR), `read:packages` (optional)
   - Repository scoping to RadiusClaim only
   - Security warnings: never commit tokens, auto-revocation if exposed, 30–90 day rotation guidance

2. **Deprecated Flag Removal:** Line 211 updated from:
   - `rad install kubernetes --set clusterType=generic --wait`
   - To: `rad install kubernetes --set clusterType=generic`
   - Rationale: `--wait` no longer supported in current Radius CLI

## Impact
- Improves user experience during GHCR authentication phase
- Reduces friction for team members setting up local development
- Follows least-privilege principle for token scoping
- Documentation now aligns with current Radius CLI capabilities

## Validation
- Walkthrough structure preserved
- No breaking changes to existing steps
- Security guidance prominent and clear

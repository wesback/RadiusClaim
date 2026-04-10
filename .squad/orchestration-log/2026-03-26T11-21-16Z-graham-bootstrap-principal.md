# Orchestration: Graham — Platform Dev (Previous Session)

**Session:** 2026-03-25 (previous)  
**Agent:** Graham (Platform Dev)  
**Model:** N/A (direct work)  
**Focus:** Bootstrap Principal ID Resolution

## Work Summary

Improved `resolve_azure_principal_id()` in scripts/bootstrap.sh to handle multiple Azure authentication modes with actionable diagnostics.

### Problem Addressed

Original implementation only handled service principal lookups, failing silently when operators used:
- User identity (interactive `az login`)
- Managed identity
- Workload identity federation without traditional service principals

### Solution Delivered

Enhanced function with:
1. Preserved existing happy paths (explicit AZURE_PRINCIPAL_ID, service principal auto-resolution)
2. Added stderr diagnostics when resolution fails
3. Context-specific guidance for each auth mode
4. Maintained stdout cleanliness for command substitution

### Files Modified

- `scripts/bootstrap.sh` — improved resolve_azure_principal_id() function and error message
- `scripts/README.md` — documented principal ID resolution
- `docs/end-to-end-setup-walkthrough.md` — added inline comments at three export locations

### Supported Auth Modes

- ✅ Service principal (client ID + secret) — auto-resolves
- ✅ Workload identity (federated credential) — auto-resolves
- ✅ User identity (interactive az login) — requires manual export
- ✅ Managed identity — requires manual export

### Decision Produced

- **File:** `.squad/decisions/inbox/graham-principal-resolution.md`
- **Status:** IMPLEMENTED
- **Operator Rule:** When auto-resolution fails, stderr diagnostics explain exactly what to do next

### Validation

- ✅ Syntax validated with `bash -n`
- ✅ Function preserves stdout cleanliness
- ✅ Diagnostics go to stderr only
- ✅ Existing happy paths unchanged

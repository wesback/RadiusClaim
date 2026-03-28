# Session Log: GHCR URL Encoding Fix

**Timestamp:** 2026-03-27T09:15:59Z  
**Agent:** Pete (Infrastructure Automation Specialist)  
**Task:** Fix GHCR package deletion URL encoding  

## Summary

Fixed a bug in `scripts/teardown.sh` where GHCR package names containing forward slashes (e.g., `radiusclaim/expense-api`) were not properly URL-encoded in GitHub API calls. The fix changes the encoding from space-only (`%20`) to forward-slash encoding (`%2F`), allowing the `delete_ghcr_packages()` function to successfully delete packages instead of returning 404 errors.

## Changes

**File:** `scripts/teardown.sh` (line 493)  
**Change:** Convert `${full_name// /%20}` to proper forward-slash encoding `${full_name//\//%2F}`

## Decision

Decision 18 logged in `.squad/decisions.md` documenting the root cause, implementation, and API standards.

## Outcome

✅ GHCR package cleanup now works correctly  
✅ Multi-level package names properly supported  
✅ Backwards compatible (transparent to script users)  

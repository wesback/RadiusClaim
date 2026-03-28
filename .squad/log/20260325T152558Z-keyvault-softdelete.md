# Session Log: Key Vault Soft-Delete Diagnosis

**Date:** 2026-03-25  
**Agent:** Graham  

## Summary

Diagnosed Azure Key Vault soft-delete collision blocking `rad deploy` on platform-secrets recipe. Confirmed expected Azure behavior, not app bug. Documented three operator recovery paths (wait for purge, new environment, manual purge). Updated validation checklist with troubleshooting guidance.

## Decision

Option A (wait for auto-purge) recommended. Options B & C documented for timeline-critical scenarios.

## Files

- `docs/radius-validation-checklist.md` — Soft-delete troubleshooting added
- `.squad/decisions/inbox/graham-keyvault-softdelete.md` — Full decision detail

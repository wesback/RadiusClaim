# Session Log: Dapr Readiness Fix

**Timestamp:** 2026-03-25T18:21:03Z  
**Focus:** Graham — prepare-cluster Dapr readiness after install  

## Summary
Fixed race condition in prepare-cluster script where readiness check could fail even on successful Dapr install. Changed to use Dapr CLI's native wait semantics (`--wait` flag) to ensure control plane health before proceeding.

## Key Changes
- Updated `scripts/prepare-cluster.sh`: Use `dapr init -k --wait` instead of `dapr init -k`
- Preserves existing `verify_dapr_ready` check as final safety gate
- Eliminates arbitrary sleeps; uses platform's documented behavior

## Decision Context
The smallest correct repair matches Dapr's documented contract for Kubernetes installs and avoids teaching arbitrary delays into platform automation.

**Status:** Complete — ready for merge into main decisions registry

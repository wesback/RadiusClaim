---
name: "native-cli-install-wait"
description: "Use a platform CLI's native wait/readiness flag when install success and runtime readiness are different events"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a setup script invokes an installer command that reports success before the installed control plane or service is actually healthy. This is common with Kubernetes-facing CLIs where "install submitted" and "pods ready" are distinct phases.

## Patterns

### Prefer the CLI's wait contract over manual sleeps

- Check whether the installer already exposes a readiness flag such as `--wait` and a bounded timeout.
- Use that native wait behavior first instead of layering fixed sleeps into the script.
- Keep the script's explicit post-install verification as a final guard.

### If the CLI has no wait flag, use the platform's authoritative rollout signal

- When the installer has no native wait/readiness option, add a bounded Kubernetes-native readiness gate that targets the same control-plane object operators inspect manually.
- Prefer `kubectl rollout status` or `kubectl wait` on the canonical deployment over ad hoc sleep loops.
- Keep the post-install verification aligned with the same control-plane selector so the install path and the troubleshooting path talk about the same runtime signal.

### Diagnose by comparing command semantics to follow-on checks

- If the installer says "success" but the script's next readiness check fails immediately, inspect the CLI help/docs before changing polling logic.
- Treat this as a contract mismatch until proven otherwise: the script assumed blocking readiness, while the CLI only confirmed submission/completion of the install action.

### Keep the fix small and local

- Change the install invocation, not every downstream readiness check, when the root cause is installer semantics.
- Avoid broad helper rewrites when one native flag closes the gap.

## Examples

- `scripts/prepare-cluster.sh`: `dapr init -k --wait` followed by existing `verify_dapr_ready`
- `scripts/prepare-cluster.sh`: `rad install kubernetes --set clusterType=generic`, then `kubectl rollout status deployment/controller -n radius-system --timeout=5m`, then existing `verify_radius_ready` (with optional fallback to legacy `radius-controller-manager` on older clusters)

## Anti-Patterns

- Adding arbitrary `sleep 30` or retry loops before checking whether the CLI already supports `--wait`
- Removing useful post-install verification because the installer now waits
- Treating "command exited 0" as equivalent to "runtime is healthy" without checking the command's documented behavior
- Waiting on a guessed pod label or resource when the docs and operator runbooks already treat a specific deployment as the authoritative readiness signal

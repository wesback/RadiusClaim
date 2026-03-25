---
name: "stdout-clean-command-substitutions"
description: "Keep bash helpers pure when their output is captured with command substitution"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a bash script captures a helper's stdout with `value=\"$(helper)\"` but the helper also performs side effects such as switching kubectl context, running a login command, or printing operator-facing progress.

## Pattern

### Separate mutation from lookup

- If a helper is called inside `$(...)`, it should print only the machine-readable value the caller expects to store.
- Move side effects into a separate helper that can log or suppress stdout intentionally.
- Keep the lookup helper responsible only for validation plus the final `printf`.

### Suppress chatty CLI output at the mutation boundary

- Commands like `kubectl config use-context` can emit human-facing status text.
- If that status text is not part of the captured value, redirect it away from stdout or run it outside the command substitution.

### Prefer a two-step shape

```bash
select_kubectl_context() {
  kubectl config use-context "$KUBE_CONTEXT" >/dev/null 2>&1
}

resolve_kubectl_context() {
  local current_context
  current_context="$(kubectl config current-context)"
  printf '%s\n' "$current_context"
}

select_kubectl_context
KUBECTL_CONTEXT="$(resolve_kubectl_context)"
```

## Examples

- `scripts/prepare-cluster.sh`

## Anti-Patterns

- Capturing a helper with `$(...)` when the helper also prints command progress
- Letting `run_cmd` output bleed into a variable that is supposed to hold only a single identifier
- Reusing one function for both "do the thing" and "tell me the resulting value"

# Skill: Idempotent Kubernetes Secret for Bootstrap-Generated Tokens

## Problem

A bootstrap script needs to generate a secret (API token, symmetric key, etc.) once, pass it to a deployment, and **not rotate it** on subsequent runs — while also never storing it in Git or hardcoding it.

## Pattern

**Store-or-read in a Kubernetes secret before deploy.**

```bash
ensure_my_token() {
  local secret_name="my-token-secret"
  local namespace="$WORKLOAD_NAMESPACE"

  # Idempotency: ensure namespace exists.
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

  if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
    MY_TOKEN="$(kubectl get secret "$secret_name" -n "$namespace" \
      -o jsonpath='{.data.token}' | base64 -d)"
    log_success "Token loaded from existing secret."
  else
    # 256-bit entropy — sufficient for API tokens, HMAC keys, etc.
    MY_TOKEN="$(openssl rand -hex 32)"
    kubectl create secret generic "$secret_name" \
      --from-literal="token=${MY_TOKEN}" \
      -n "$namespace" >/dev/null
    log_success "Token generated and stored in secret '${secret_name}'."
  fi
}
```

Then pass to the deploy tool:
```bash
--parameters "myToken=${MY_TOKEN}"
```

In Bicep, mark the parameter `@secure()` so Radius/ARM never logs it:
```bicep
@secure()
param myToken string
```

## Key Properties

- **Idempotent**: re-running bootstrap uses the existing token.
- **No Git exposure**: token lives only in the cluster.
- **Rotation**: delete the secret manually → next bootstrap generates a new one.
- **Dry-run safe**: use a placeholder when `DRY_RUN=true`.

## Applied In

- `scripts/bootstrap.sh` → `ensure_dapr_app_api_token()` (Dapr App API token)
- `infra/radius/app.bicep` → `param appApiToken string` with `@secure()`

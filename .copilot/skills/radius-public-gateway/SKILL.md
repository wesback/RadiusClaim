---
name: "radius-public-gateway"
description: "Expose one Radius-managed Kubernetes service publicly with a gateway while keeping worker services internal"
domain: "platform"
confidence: "high"
source: "earned"
tools:
  - name: "web_fetch"
    description: "Confirm current Radius gateway/container schema details"
    when: "You need exact gateway resource shape or hostname behavior"
  - name: "bash"
    description: "Rebuild Bicep JSON artifacts and run validation commands"
    when: "You changed Radius models or deployment workflow expectations"
  - name: "rg"
    description: "Sweep docs and workflows for stale port-forward-only wording"
    when: "Public exposure changes the operator story"
---

## Context

Use this when a Radius-managed Kubernetes deployment needs one public HTTP entrypoint, especially for a hosted UI or API, without exposing worker services or dropping into hand-written Kubernetes ingress YAML.

## Patterns

### Add a Radius gateway in the app model

- Add `Applications.Core/gateways@2023-10-01-preview` to the same `app.bicep` that declares the containers.
- Route `path: '/'` to the public-facing service (`http://expense-api:8080` in this repo).
- Keep the gateway tied to the Radius application so public exposure stays in the same model as service wiring.

### Make hostname intent explicit

- Provide a default hostname prefix for generated nip.io endpoints.
- Allow an optional fully-qualified hostname override for teams that want their own DNS.
- Teach operators that `rad deploy` prints the resolved public endpoint and that this line is operationally important.

### Keep workers internal

- Expose only the service that owns the UI/API boundary.
- Continue observing worker services through logs and internal service discovery, not direct public endpoints.

### Update validation expectations, not just infra

- Update README, deployment checklists, and demo walkthroughs so the public gateway is the preferred human path.
- Keep `kubectl port-forward` as a fallback for CI or for clusters where external address propagation lags.
- Rebuild checked-in JSON generated from the Bicep source when the app model changes.

## Examples

- `infra/radius/app.bicep`
- `infra/radius/app.json`
- `.github/workflows/deploy-azure.yml`
- `docs/radius-validation-checklist.md`
- `docs/phase-7-demo-walkthrough.md`

## Anti-Patterns

- Adding hand-written Kubernetes Ingress/Gateway YAML when Radius gateways already cover the need.
- Publishing worker services just because they are easy to reach through cluster routing.
- Leaving docs or CI text implying port-forward is still the only supported user path after a public gateway exists.

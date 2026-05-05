---
name: "platform-contract-alignment"
description: "Keep sample architecture docs, scripts, tests, and app model aligned"
domain: "platform-review"
confidence: "high"
source: "graham-review-2026-05-05"
---

## Context

Reference samples are judged by their teachable contract, not just by whether one happy-path deployment works.
When the app model, bootstrap flow, tests, and README drift apart, operators learn the wrong platform story and reviewers get false confidence.

## Pattern

- Treat these files as a single contract surface:
  - `infra/radius/app.bicep`
  - `infra/radius/environments/*`
  - deployment/bootstrap scripts
  - portability/validation tests
  - README / walkthrough docs
- When one of these changes, audit all of the others in the same pass.
- Verify that every advertised deployment path has matching implementation artifacts (recipes, publish flow, validation, docs).

## Review checklist

1. **Ingress alignment** — If docs or scripts mention a gateway/route, confirm the app model declares it.
2. **Recipe alignment** — If an environment references recipe artifacts, confirm the repo can publish them.
3. **Namespace alignment** — Ensure docs, scripts, and tests use the same runtime namespace convention.
4. **Secret/auth alignment** — If app code expects a token/secret in production, confirm the platform model injects it.
5. **State/backend alignment** — Ensure docs and recipe READMEs describe the actual backing resource in use.
6. **Invocation alignment** — If app code uses Dapr app IDs for service invocation, the Radius model should not also depend on raw `http://service:port` assumptions for the same edge.

## Anti-patterns

- Docs promising a local or multi-environment path that the publish pipeline cannot produce.
- Scripts querying resources (gateways, components, namespaces) that the app model never creates.
- Validation scripts that pass despite checking stale defaults or the wrong runtime shape.
- README examples that describe a previous backend after the recipes have changed.
- App code that fail-closes on a production token/secret contract that the Radius app model never injects.
- Radius connections that hardcode Kubernetes DNS/ports even though the application edge is intentionally modeled through Dapr app IDs.

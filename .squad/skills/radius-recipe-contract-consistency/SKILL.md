---
name: "radius-recipe-contract-consistency"
description: "Keep Radius environment recipes, bootstrap preflight logic, and app model contracts aligned"
domain: "platform"
confidence: "high"
source: "rod-earned"
---

## Context

Use this when a Radius app depends on environment-registered recipes plus bootstrap or validation scripts that predict resource names, pass recipe parameters, or clean up stale resources.

## Pattern

1. Treat each recipe Bicep file as the source of truth for:
   - required parameters
   - resource naming formulas
   - output resource identity
2. Make every environment Bicep pass the full required parameter contract for the recipe it registers.
3. If bootstrap or teardown predicts a recipe-created Azure resource name, derive it from the exact same inputs and formula as the recipe.
4. Prefer stable per-environment naming for repeatable deploys; do not generate a fresh suffix on every deploy unless teardown also reclaims the old resources.

## Checks

- Compare `infra/radius/environments/*.bicep` recipe `parameters` blocks against the target recipe Bicep parameter list.
- Compare bootstrap preflight naming logic against the recipe's `var` naming logic byte-for-byte in intent.
- Verify the app model’s requested recipe names actually exist in the target environment, or intentionally rely on `default`.
- Re-run deploy logic mentally for a second deployment and check whether it updates in place or creates parallel resources.

## Anti-Patterns

- **Shadow naming logic in scripts** — a preflight script computes `ce-*` while the recipe deploys `kvrc*`.
- **Per-run random suffixes for shared backing resources** — every redeploy creates new Key Vault, Service Bus, or PostgreSQL names.
- **Half-wired environments** — dev/local environments register a recipe but do not pass the parameters that recipe requires.

---
name: "radius-azure-recipe-troubleshooting"
description: "Diagnose Radius Azure recipe failures by separating provider credential bootstrap issues from recipe output-contract bugs"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when `rad deploy` fails on Azure-backed Radius recipes with a mix of:
- missing `azure-azurecloud-default` errors, or
- ARM/recipe errors saying Azure resources are not defined in the template.

This fits Kubernetes-first Radius environments where Azure backing services are provisioned through OCI-published Bicep recipes.

## Patterns

### Treat Azure provider credentials as bootstrap, not app config

- If Radius says it cannot find Kubernetes secret `azure-azurecloud-default`, assume the active Radius installation is missing its Azure provider credential.
- Repair with `rad credential register azure ...` against the same workspace/cluster hosting Radius.
- In CI/CD, put the credential-registration step before environment or app deployment. Publishing recipes and deploying `azure-radius.bicep` is not enough by itself.

### Keep Azure recipe `result.resources` clean

- For **Bicep recipes creating Azure/AWS resources**, let Radius auto-populate backing resources.
- Prefer omitting `result.resources` entirely when the recipe only creates cloud-native backing resources; the generated JSON mirror should lose the `outputs.result.value.resources` block too.
- Only manually populate `output result.resources` for **Kubernetes/UCP IDs** that the deployment engine cannot infer.
- If a recipe manually emits Azure resource IDs like storage accounts, Service Bus namespaces, or Key Vaults, treat that as suspicious contract drift.

### Review the three layers in order

1. **Bootstrap layer:** `rad credential register azure ...`
2. **Environment layer:** `infra/radius/environments/azure-radius.bicep` provider scope + recipe registry/tag
3. **Recipe layer:** `infra/radius/recipes/azure/*.bicep` output contract and parameter alignment

### Republish after recipe fixes

- If a recipe Bicep file changes, regenerate the checked-in JSON mirror and republish the OCI artifacts before retrying `rad deploy`.
- Do not assume the live environment is using local source files; `templatePath` points at published artifacts.

## Examples

- Workflow bootstrap gap: `.github/workflows/deploy-azure.yml`
- Environment contract: `infra/radius/environments/azure-radius.bicep`
- Recipe files:
  - `infra/radius/recipes/azure/state-store.bicep`
  - `infra/radius/recipes/azure/pubsub.bicep`
  - `infra/radius/recipes/azure/secrets.bicep`

## Anti-Patterns

- Treating `azure-azurecloud-default` as an app secret name bug in `app.bicep`.
- Debugging `app.bicep` first when the Azure provider credential is missing.
- Manually listing Azure resource IDs in Bicep recipe `result.resources`.
- Fixing recipe source without republishing the OCI artifacts referenced by the environment.

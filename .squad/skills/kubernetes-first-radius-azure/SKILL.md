---
name: "kubernetes-first-radius-azure"
description: "Pattern for a Kubernetes-first Radius deployment story with Azure-backed services kept explicit"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when Radius is the primary deployment contract, Kubernetes is the compute target, and Azure still provides the backing services through recipes. It fits repos that want one honest deployment story instead of a split between Radius orchestration and direct Azure runtime fallbacks.

## Patterns

### Center workflow choice on Kubernetes targets

- Keep a single deployment job for the Radius-managed Kubernetes path.
- If the workflow needs a switch, make it a cluster profile selector such as `kubernetes_target` (`aks`, `arc-enabled`, `self-managed`), not a runtime-mode toggle.
- Validate the selector early so repository variables cannot silently drift into unsupported values.
- Treat namespace migrations as direct environment-default updates (`radiusclaim-dev`, `radiusclaim-azure`), not as a reason to add dual-namespace compatibility branches or alias logic in the shared sample.

### Keep Azure specifics explicit but secondary

- Treat `infra/radius/environments/azure-radius.bicep` as the authoritative Azure-backed Kubernetes environment.
- Keep `infra/radius/environments/azure.bicep` only as a legacy ACA reference when it still teaches something, and label it clearly as non-primary.
- Make the environment outputs say both truths: compute is Kubernetes-portable, backing services are still Azure Blob Storage, Service Bus, and Key Vault.
- When a Dapr resource uses `resourceProvisioning: 'recipe'`, keep `type`, `version`, and `metadata` in the recipe output object, not on the application resource itself; Radius rejects mixed manual+recipe declarations.
- Register recipe `templatePath` values as OCI artifacts (for example GHCR), not local relative files, or `rad deploy` will fail when the control plane tries to download the recipe.
- For Azure Key Vault recipes, never set `enablePurgeProtection: false`; Azure treats purge protection as a one-way control and that value causes deployment failures. In the base sample, omit the property instead of forcing `true`, so the sample stays small and avoids turning a deployment walkthrough into an irreversible Key Vault lifecycle lesson.

### Recover provider-missing app deploys by repairing the environment, not the app model

- If `rad deploy infra/radius/app.bicep` fails with `InvalidDeployment` and says to ensure an Azure provider is configured, treat that as an environment problem: the active Radius environment is missing `providers.azure.scope`.
- The shortest safe recovery is: bootstrap/switch to any temporary environment if needed, deploy `infra/radius/environments/azure-radius.bicep` with `azureProviderScope` and `location`, switch to the resulting `azure` environment, then rerun `rad deploy infra/radius/app.bicep`.
- To distinguish a bad environment from a bad selection, inspect both `rad workspace show -o json` and `rad env show azure -o json`: if the workspace already points at `azure` but the environment lacks `properties.providers.azure.scope` or still shows placeholder recipe parameters like `<your-azure-region>`, Radius is targeting the right environment name and the environment state itself needs repair.
- Do not “fix” this by editing `app.bicep`; the app model already assumes `rad` injects the environment id and that Azure-backed recipes come from the active environment contract.
- Mixed namespace output is expected in this recovery path: `Applications.Core/*` remains the stable app/environment owner, `Applications.Dapr/*` remains the truthful Dapr contract, and the only currently documented non-blocking build warnings are `BCP081` on `Radius.Compute/*`.

### Keep generated platform artifacts in sync

- Regenerate checked-in JSON artifacts when Bicep changes so operators and reviewers do not read stale compiled output.
- Validate the primary and legacy environment Bicep files in CI before any image build or deployment work begins.

## Examples

- Workflow anchor: `.github/workflows/deploy-azure.yml`
- Primary environment model: `infra/radius/environments/azure-radius.bicep`
- Generated contract mirror: `infra/radius/environments/azure-radius.json`
- Legacy reference only: `infra/radius/environments/azure.bicep`

## Anti-Patterns

- Keeping `deployment_mode` branching after the repo has already chosen Kubernetes as the truthful primary path.
- Claiming portability while hiding that the current Dapr backings still land on Azure services.
- Letting compiled JSON artifacts drift away from the Bicep sources reviewers are supposed to trust.

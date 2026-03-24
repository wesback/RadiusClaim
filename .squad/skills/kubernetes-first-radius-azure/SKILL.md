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

### Keep Azure specifics explicit but secondary

- Treat `infra/radius/environments/azure-radius.bicep` as the authoritative Azure-backed Kubernetes environment.
- Keep `infra/radius/environments/azure.bicep` only as a legacy ACA reference when it still teaches something, and label it clearly as non-primary.
- Make the environment outputs say both truths: compute is Kubernetes-portable, backing services are still Azure Blob Storage, Service Bus, and Key Vault.

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

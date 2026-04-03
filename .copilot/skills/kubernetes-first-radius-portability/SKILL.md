---
name: "kubernetes-first-radius-portability"
description: "Pattern for centering Radius deployments on Kubernetes while keeping Azure-specific backings explicit"
domain: "platform"
confidence: "high"
source: "graham-earned"
---

## Context

Use this when a Radius sample or service should frame portability around Kubernetes targets instead of a runtime-specific Azure fallback. It fits repos that use AKS as the managed Azure example but also want honest room for Arc-enabled Kubernetes / Azure Local and self-managed clusters.

## Patterns

### Keep Radius as the control plane

- Make the Radius workflow target Kubernetes directly instead of branching into runtime-specific deployment jobs.
- Keep the application model in `infra/radius/app.bicep` and the Azure-backed environment model in `infra/radius/environments/azure-radius.bicep`.
- Preserve stable Dapr component names so app code does not care whether the cluster is AKS, Arc-enabled, or self-managed.

### Frame portability around Kubernetes targets

- Use AKS as the managed Azure example in workflow text and docs.
- State clearly that Arc-enabled Kubernetes / Azure Local and self-managed clusters are supported when Radius can reach the cluster and the environment prerequisites are met.
- If a workflow input remains, make it describe Kubernetes target profiles rather than Azure Container Apps fallback modes.

### Stay honest about cloud-specific backings

- Keep Azure Blob Storage, Service Bus, and Key Vault called out as Azure-specific recipes or dependencies.
- Prefer `kubectl port-forward` and `kubectl logs` for validation evidence so the workflow logic stays portable across Kubernetes targets.
- Sweep stale naming residue (retired product names, old namespaces, old image prefixes) in the same files when it directly touches the platform story.

## Examples

- `.github/workflows/deploy-azure.yml`
- `infra/radius/environments/azure-radius.bicep`
- `scripts/README.md`

## Anti-Patterns

- Keeping an ACA fallback branch after portability has become the priority.
- Claiming the deployment is fully cloud-agnostic while the recipes still provision Azure backing services.
- Leaving workflow text or namespace defaults tied to retired product names after a platform pivot.

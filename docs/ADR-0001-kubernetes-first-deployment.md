# ADR-0001: Kubernetes-First Deployment Strategy with Azure Backing Services

> **Date:** 2026-03-24  
> **Status:** ACCEPTED  
> **Context:** GitHub Actions workflow deployment strategy  
> **Decision Drivers:** Portability-first, cloud-agnostic Radius, honest backing-service scope

---

## Summary

The GitHub Actions workflow (`.github/workflows/deploy-azure.yml`) deploys RadiusClaim to **Kubernetes with Dapr and Radius** as the primary path. The sample uses **Azure Kubernetes Service (AKS)** as the concrete example, with Azure backing services (Blob Storage, Service Bus, Key Vault).

This ADR documents:
1. **Why Kubernetes + Radius is the primary path**
2. **What makes the app portable and what doesn't**
3. **What Azure backing services mean for portability**
4. **How other clouds and self-managed Kubernetes fit in**

---

## Problem

**RadiusClaim demonstrates Dapr + Radius portability:** The same app code should run on any Kubernetes cluster with Dapr and Radius, regardless of the backing services.

**Azure backing services are the only cloud-specific part:** The sample uses Azure Blob Storage (state store), Azure Service Bus (pub/sub), and Azure Key Vault (secrets) because those are the concrete examples in the Radius recipes. But the app code itself is cloud-agnostic.

**Portability is enabled by:**
1. **Dapr abstractions** — state, pub/sub, service invocation, workflows are decoupled from infrastructure
2. **Radius recipes** — define which backing services are used; recipes can be swapped without changing app code
3. **Environment definitions** — `azure-radius.bicep` uses Azure recipes; future environments could use other clouds

**The honest scoping:**
- ✅ **Compute is portable:** Kubernetes (AKS, Arc, self-managed) all work the same
- ✅ **Dapr components are portable:** Same component names and interfaces across all environments
- ✅ **App code is portable:** Uses only Dapr APIs, no Azure-specific code
- ❌ **Backing services are tied to recipes:** Azure recipes provide Azure services; other cloud recipes (if available) would provide their equivalents

---

## Decision

**The GitHub Actions workflow deploys to Kubernetes via Radius as the primary (and only) path.**

### Primary Path: Kubernetes + Radius with Azure Example

**What happens:**
1. Builds service Docker images
2. Pushes images to GHCR (GitHub Container Registry)
3. Runs `rad deploy infra/radius/environments/azure-radius.bicep` to configure the Radius Azure environment (authenticates to Azure subscription, sets up provider)
4. Runs `rad deploy infra/radius/app.bicep` to deploy the application model to the Kubernetes cluster

**What Radius provides:**
- Service topology (three containers: expense-api, workflow-engine, notification-svc)
- Dapr component declarations (statestore, pubsub, platform-secrets)
- Connection/wiring definitions (which services connect to which components)
- Kubernetes manifest generation
- Dapr sidecar injection
- Azure backing resource provisioning via recipes (Blob Storage, Service Bus, Key Vault)

**Where it runs:**
- **AKS (Azure Kubernetes Service)** — the primary example in this sample
- **Arc-enabled Kubernetes** — on-premises or multi-cloud K8s with Radius control plane and Azure recipes
- **Self-managed Kubernetes** — any K8s cluster with Dapr and Radius control plane; can use Azure recipes if Azure access is available, or custom recipes for other backings

**Who should use this path:**
- Teams with a Kubernetes cluster and Radius installed (or planning to install it)
- Teams prioritizing application portability across environments
- Demonstrations of Dapr + Radius portability patterns

---

## Current Coverage (Phase 7 Status)

| Concern | Kubernetes + Radius |
|---------|---------------------|
| **Compute** | ✅ Any Kubernetes (AKS, Arc, self-managed) |
| **Service topology** | ✅ Declarative (app.bicep) |
| **Dapr components** | ✅ Declarative (app.bicep) |
| **Azure backing resources** | ✅ Recipes (azure/*.bicep) |
| **Connection/wiring** | ✅ Declarative (app.bicep links) |
| **App code portability** | ✅ Yes (Dapr APIs only) |
| **Deployment model portability** | ✅ Yes (Radius recipes define environment) |
| **Backing services portability** | ⚠️ Tied to recipe choice (Azure recipes = Azure services; other recipe implementations = equivalents) |
| **Kubernetes required** | ✅ Yes |
| **Container registry** | GHCR (or any OCI registry) |

---

## Why Kubernetes-First?

1. **Radius is Kubernetes-native.** Radius control planes run on Kubernetes; Kubernetes is the primary deployment target.
2. **AKS is the concrete example.** This sample demonstrates Azure backing services with Kubernetes, not as a Kubernetes alternative.
3. **Portability starts at compute.** Once Kubernetes is the baseline, any K8s cluster (AKS, Arc, self-managed) works the same way.
4. **Recipes enable cloud variety.** Different recipe implementations can target different clouds without changing the app model or deployment narrative.
5. **Honesty about scope.** Backing services are tied to recipes; that's transparent and correct.

---

## Portability in Practice: Azure Local and Arc-Enabled Kubernetes

**Kubernetes + Radius is the deployment model.** Portability is enabled through recipe swapping and environment definitions.

### Concrete Portability Example: Azure Local and Arc-Enabled Kubernetes

This sample demonstrates portability on **Azure Local** (edge devices) and **Arc-enabled Kubernetes** (on-premises and multi-cloud clusters):

- **Azure Local (edge):** Deploy with `azure-radius.bicep` environment to Azure Local devices running Kubernetes
- **Arc-enabled Kubernetes (on-premises):** Deploy with the same `azure-radius.bicep` environment to on-premises clusters registered with Azure Arc
- **Self-managed Kubernetes:** Deploy to any Kubernetes cluster with Dapr and Radius control plane; use Azure recipes if Azure subscription access is available, or bring custom recipes for alternative backing services

**The same app model, Dapr components, and deployment artifacts work across all three targets.** Only the Kubernetes cluster target changes; the Radius environment and recipes remain stable.

```
expense-api     ─┐
workflow-engine ─┼─> [Radius] ─> Azure Recipes (Blob, Service Bus, Key Vault)
notification-svc─┘                 │
                                    └─> Runs on: AKS | Azure Local | Arc-Enabled K8s | Self-Managed K8s
```

**No app code changes. No Dapr component name changes. No contract changes.**

### Future: Recipes for Other Cloud Platforms

If and when Radius recipes for other clouds become available, the same pattern applies:
- New environment definition (e.g., `aws-radius.bicep` or `gcp-radius.bicep`) with equivalent Radius recipes
- Same app model (`infra/radius/app.bicep`)
- Same deployment workflow, pointing to the new environment

Teams can maintain multiple environment definitions in a single repository and switch between them without changing application code.

---

## Maintenance Obligations

This Kubernetes-first path must continue to satisfy:

1. **Dapr parity:** The deployment must keep the same Dapr components (`statestore`, `pubsub`, `platform-secrets`) with identical names across environments
2. **Service parity:** The deployment must keep the same three services (`expense-api`, `workflow-engine`, `notification-svc`) with compatible configurations
3. **Contract stability:** The deployment must preserve the same RadiusClaim contract shapes and threshold rules ($100.00 boundary, UTC timestamps, etc.)
4. **Demo evidence:** The deployment must keep producing observable, traceable end-to-end flows (as documented in the Phase 7 demo walkthrough)
5. **Documentation:** The repo must keep the operator walkthrough, troubleshooting guidance, and portability narrative aligned with the current workflow

---

## Application Code Impact

**None.** The application code is agnostic to which deployment target is used:

- All three services use Dapr APIs for state, pub/sub, secrets, and service invocation
- Service names and Dapr component names are stable across all environments (Azure, Arc-enabled, self-managed)
- The Radius environment choice is invisible to the application once deployed

**This is the point of the design:** Dapr ensures the app is portable; Radius handles the infrastructure wiring. Swapping environments or backing-service recipes does not require code changes.

---

## Example: Deploying to Azure Local or Arc-Enabled Kubernetes

To deploy to **Azure Local** (edge) or **Arc-enabled Kubernetes** (on-premises or multi-cloud), a user:

1. Ensures the cluster is **registered with Azure Arc** (or is Azure Local)
2. Installs **Dapr and Radius control plane** on the cluster
3. Configures **Azure credentials** (subscription ID, resource group) for backing services
4. Runs the same workflow (or `rad deploy` locally) pointing to the `azure-radius.bicep` environment
5. Observes the same demo flow ($50 auto-approve, $150 manual review, end-to-end notifications), using the same Azure backing services

**No app code changes. No Dapr config changes. No contract changes. The only difference is the Kubernetes cluster target.**

This pattern demonstrates true portability: the same application and infrastructure model runs across AKS, Azure Local, Arc-enabled clusters, and self-managed Kubernetes—as long as the cluster has Dapr and Radius installed and can reach Azure for backing services.

---

## References

- **Radius Docs:** https://docs.radapp.io/
  - Environments: https://docs.radapp.io/concepts/environments/overview
  - Recipes: https://docs.radapp.io/concepts/recipes/overview
  - Compute: https://docs.radapp.io/concepts/architecture-overview#compute-concepts
- **Azure Kubernetes Service Docs:** https://learn.microsoft.com/en-us/azure/aks/
- **GitHub Actions Secrets:** https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
- **RadiusClaim Repo:** `.github/workflows/deploy-azure.yml`

---

## Decision Log

- **Proposed:** 2026-03-24 (Phase 7, Eddie)
- **Reviewed by:** Daisy (Lead), Wesley (Owner)
- **Accepted:** 2026-03-24
- **Rationale:** Kubernetes-first deployment clarity + honest portability scope + cloud-agnostic recipes roadmap

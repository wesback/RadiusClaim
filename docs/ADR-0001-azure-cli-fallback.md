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
- ❌ **Backing services are tied to recipes:** Azure recipes provide Azure services; AWS/GCP recipes would provide their equivalents

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
| **Backing services portability** | ⚠️ Tied to recipe choice (Azure recipes = Azure services; future AWS/GCP recipes = equivalents) |
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

## Roadmap: Enabling Other Clouds

**Kubernetes + Radius is the deployment model.** To support other clouds, we need Radius recipes for those clouds.

### Option A: AWS Recipes (DynamoDB, SQS, Secrets Manager)

If Radius recipes for AWS are created, the app model in `infra/radius/app.bicep` and the deployment workflow remain unchanged. Only the environment definition switches:
- Deploy to EKS (or any K8s on AWS) with `aws-radius.bicep` environment
- Radius recipes provision AWS backing services instead of Azure

**No app code changes. No Dapr component names changes.**

### Option B: GCP Recipes (Firestore, Pub/Sub, Secret Manager)

Similar to AWS: same app model, new environment definition with GCP recipes, deploy to GKE or any K8s on GCP.

### Option C: Hybrid Multi-Cloud

Teams can define multiple environments in the Radius model:
- `azure-radius.bicep` for AKS deployments
- `aws-radius.bicep` for EKS deployments
- `gcp-radius.bicep` for GKE deployments
- `self-managed.bicep` for on-premises or private Kubernetes

Deploy the same app to any cloud by choosing the target environment.

---

## Maintenance Obligations

While both paths exist, they must satisfy:

1. **Dapr parity:** Both paths must wire the same Dapr components (`statestore`, `pubsub`, `platform-secrets`) with identical names
2. **Service parity:** Both paths must deploy the same three services (`expense-api`, `workflow-engine`, `notification-svc`) with compatible configurations
3. **Contract stability:** Both paths must support the same RadiusClaim contract shapes and threshold rules ($100.00 boundary, UTC timestamps, etc.)
4. **Demo evidence:** Both paths must produce observable, traceable end-to-end flows (as documented in Phase 7 demo walkthrough)
5. **Documentation:** Both paths must be documented, and the narrative must clearly indicate which is primary and why the fallback exists

---

## Application Code Impact

**None.** The application code is agnostic to which deployment target is used:

- All three services use Dapr APIs for state, pub/sub, secrets, and service invocation
- Service names and Dapr component names are stable across all environments (Azure, AWS, GCP, self-managed)
- The Radius environment choice is invisible to the application once deployed

**This is the point of the design:** Dapr ensures the app is portable; Radius handles the infrastructure wiring. Swapping environments or backing-service recipes does not require code changes.

---

## Example: Swapping to AWS

To deploy to AWS Kubernetes (EKS), a user:

1. Adds AWS credentials to GitHub Actions secrets (or uses AWS IAM role)
2. Switches the Radius environment from `azure-radius.bicep` to `aws-radius.bicep` (or creates a new GitHub Actions workflow variable to parameterize it)
3. Runs the workflow
4. Observes the same demo flow ($50 auto-approve, $150 manual review, end-to-end notifications), but with AWS backing services

**No code changes. No Dapr config changes. No contract changes.**

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

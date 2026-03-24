# ADR-0001: Azure CLI Fallback Path for Container Apps Deployment

> **Date:** 2026-03-24  
> **Status:** ACCEPTED  
> **Context:** GitHub Actions workflow deployment strategy  
> **Decision Drivers:** Radius maturity gap, operational necessity, honest roadmap

---

## Summary

The GitHub Actions workflow (`.github/workflows/deploy-azure.yml`) offers two deployment paths:

1. **Radius-first (default):** Deploys via `rad deploy` against `infra/radius/app.bicep` and `infra/radius/environments/azure-radius.bicep`
2. **Azure CLI fallback:** Deploys directly to Azure Container Apps via `az deployment` and `az containerapp` commands

This ADR documents **why the fallback exists today**, **what Radius covers now**, and **what must change for the fallback to disappear**.

---

## Problem

**RadiusClaim aims to demonstrate Radius as the primary deployment contract.** Radius provides a portable, environment-agnostic application model that works across Kubernetes clusters and cloud platforms.

**However, Radius does not currently expose Azure Container Apps as a supported compute kind.** The Radius roadmap treats ACA support as a future enhancement. This creates a gap:

- **Radius can model services, Dapr components, and connections** (as shown in `infra/radius/app.bicep`)
- **Radius cannot directly provision or manage Azure Container Apps containers**

This leaves two options:

1. **Abandon the Azure-on-ACA demonstration** and only show deployment to Kubernetes + Radius
2. **Keep an honest fallback path** that handles the ACA gap while remaining transparent about why it exists

We chose option 2.

---

## Decision

**The GitHub Actions workflow includes both a Radius-first path and an ACA-fallback path.**

### Radius-First Path (`.github/workflows/deploy-azure.yml`, `deployment_mode=radius-first`)

**What happens:**
1. Builds service Docker images
2. Pushes images to GHCR (GitHub Container Registry)
3. Runs `rad deploy infra/radius/environments/azure-radius.bicep` to configure the Radius Azure environment
4. Runs `rad deploy infra/radius/app.bicep` to deploy the application model

**What Radius provides:**
- Service topology (three containers: expense-api, workflow-engine, notification-svc)
- Dapr component declarations (statestore, pubsub, platform-secrets)
- Connection/wiring definitions (which services connect to which components)
- Kubernetes manifest generation
- Dapr sidecar injection
- Azure backing resource provisioning via recipes (Blob Storage, Service Bus, Key Vault)

**What Radius does NOT provide:**
- Direct Azure Container Apps provisioning
- ACA scaling policies, traffic splitting, or managed identity configuration
- ACA-specific ingress or networking setup

**Who should use this path:**
- Teams with a Kubernetes cluster and Radius installed
- Teams prioritizing application portability over "zero Kubernetes" operations
- Demonstrations of Radius as a platform-agnostic deployment model

---

### ACA Fallback Path (`.github/workflows/deploy-azure.yml`, `deployment_mode=aca-fallback`)

**What happens:**
1. Builds service Docker images
2. Pushes images to Azure Container Registry (ACR)
3. Runs `az deployment group create infra/radius/environments/azure.bicep` to provision:
   - Resource group
   - Azure Container Registry
   - Container Apps environment
   - Azure Blob Storage (state store)
   - Azure Service Bus (pub/sub)
   - Azure Key Vault (secrets)
4. Runs `az containerapp create/update` to deploy each service with:
   - Dapr sidecar configuration
   - Managed identity bindings
   - Health probes
   - Ingress routing (external for expense-api, internal for workflow-engine, none for notification-svc)
   - Container resources (CPU, memory)

**What this path provides:**
- Fully Azure-managed deployment (no Kubernetes required)
- Direct Azure Container Apps support
- Azure-specific features (managed identity, Traffic Manager, Azure Monitor integration)
- Faster provisioning for teams without Kubernetes infrastructure

**What this path loses:**
- Portability — this is Azure-specific and cannot easily move to another cloud
- Declarative application model — Azure-specific Bicep and CLI commands must be maintained separately
- Dapr component abstraction — services still use Dapr APIs, but the backing infrastructure is hard-coded to Azure

**Who should use this path:**
- Teams with "cloud = Azure" as a strategic decision
- Teams who want managed services without operating Kubernetes
- Proof-of-concept or testing scenarios where portability is not a priority

---

## Current Coverage (Phase 6 Status)

| Concern | Radius-First | ACA Fallback |
|---------|--------------|--------------|
| **Service topology** | ✅ Declarative (app.bicep) | ⚠️ CLI scripted (az containerapp) |
| **Dapr components** | ✅ Declarative (app.bicep) | ✅ CLI provisioned (azure.bicep) |
| **Azure backing resources** | ✅ Recipes (azure/*.bicep) | ✅ Direct ARM (azure.bicep) |
| **Connection/wiring** | ✅ Declarative (app.bicep links) | ⚠️ Manual (environment setup) |
| **Portability** | ✅ Yes (Radius + recipes + Dapr) | ❌ No (Azure-specific) |
| **Kubernetes required** | ✅ Yes | ❌ No |
| **GHCR or ACR** | GHCR | ACR |
| **Environment parity** | ✅ Recipes define consistency | ⚠️ Must match manually |

---

## Why Both Paths Today?

1. **Radius gap is real.** Radius genuinely does not support ACA today, and that gap affects real teams.
2. **Azure is the target.** The sample aims to show Azure Container Apps as the primary example; keeping Radius-only would miss that audience.
3. **Honesty is credible.** Labeling the fallback clearly (not hiding it as the "production path") teaches teams about platform readiness.
4. **Workflow investment is small.** Maintaining both paths is ~150 lines of YAML; the cost is acceptable for the benefit.

---

## Roadmap: When the Fallback Can Disappear

**The ACA fallback path can be removed when any of these occur:**

### Option A: Radius Adds ACA Support

If the Radius project adds Azure Container Apps as a supported compute kind, the app model in `infra/radius/app.bicep` could target ACA directly. No app code or Dapr component names need to change.

**Timeline:** Unknown (Radius roadmap item, not committed)

### Option B: ACA Supports the Kubernetes API

If Azure Container Apps gains first-class Kubernetes API compatibility, the Radius-first path could deploy directly to ACA without the separate Azure provider and recipes.

**Timeline:** Unknown (Azure roadmap)

### Option C: Alternate Platform Emerges

If an alternate platform (e.g., Nomad, Cloud Foundry, OpenShift) becomes the strategic choice, the workflow could swap the ACA fallback for that platform's deployment path.

**Timeline:** Dependent on organizational strategy

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

**None.** The application code is agnostic to which deployment path is used:

- All three services use Dapr APIs for state, pub/sub, secrets, and service invocation
- Service names and Dapr component names are stable across both paths
- The workflow's choice of deployment target is invisible to the application once deployed

**This is the point of the design:** Dapr ensures the app is portable; Radius (or the ACA fallback) handles the infrastructure wiring. Swapping between them does not require code changes.

---

## Example: Swapping to ACA Fallback

To use the ACA fallback path, a user:

1. Adds required secrets to GitHub Actions: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
2. Adds required variables: `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`, `AZURE_ACR_NAME`
3. Runs the workflow with `deployment_mode=aca-fallback` (either via `workflow_dispatch` or `AZURE_DEPLOYMENT_MODE` variable)
4. Observes the same demo flow ($50 auto-approve, $150 manual review, end-to-end notifications)

**No code changes. No Dapr config changes. No contract changes.**

---

## References

- **Radius Docs:** https://docs.radapp.io/
  - Environments: https://docs.radapp.io/concepts/environments/overview
  - Recipes: https://docs.radapp.io/concepts/recipes/overview
  - Compute: https://docs.radapp.io/concepts/architecture-overview#compute-concepts
- **Azure Container Apps Docs:** https://learn.microsoft.com/en-us/azure/container-apps/
- **GitHub Actions Secrets:** https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
- **RadiusClaim Repo:** `.github/workflows/deploy-azure.yml`

---

## Decision Log

- **Proposed:** 2026-03-24 (Phase 6 completion, Graham + Eddie)
- **Reviewed by:** Daisy (Lead), Wesley (Owner)
- **Accepted:** 2026-03-24
- **Rationale:** Honest gap acknowledgment + practical Azure demo path + forward-looking roadmap

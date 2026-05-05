# Getting Started with RadiusClaim

> **What is RadiusClaim?** A reference application demonstrating how to build portable distributed systems using **Dapr** (app-layer abstractions) and **Radius** (infrastructure-as-code), deployed on **Kubernetes with Azure backing services**.

---

## Quick Start: Deploy in 2 Minutes

RadiusClaim deploys via **two shell scripts** that handle the full workflow:

```bash
# Step 1: Prepare your cluster (one time per cluster)
./scripts/prepare-cluster.sh \
  --resource-group radiusclaim-rg \
  --location belgiumcentral \
  --aks-cluster-name radiusclaim-aks \
  --create-aks \
  --create-spn \
  --install-dapr \
  --install-radius \
  --yes

# Step 2: Deploy the app (repeatable for updates)
./scripts/bootstrap.sh \
  --resource-group radiusclaim-rg \
  --create-spn \
  --yes
```

For details, see [**Deployment Guide**](./end-to-end-setup-walkthrough.md).

---

## For Different Audiences

### 🏗️ **Platform Engineers / Operators**
- **Goal:** Deploy and troubleshoot RadiusClaim on AKS
- **Start here:** [Deployment Guide](./end-to-end-setup-walkthrough.md) — complete walkthrough with two-script path and manual options
- **Companion:** [Validation & Troubleshooting Checklist](./radius-validation-checklist.md) — pre-flight validation and debugging
- **Learn more:** [Kubernetes-First Deployment Strategy](./ADR-0001-kubernetes-first-deployment.md) — why this architecture was chosen; [Observability & Monitoring](./OBSERVABILITY.md) — setup and diagnostics; [Scaling Boundaries](./SCALING.md) — limits and mitigation strategies

### 👨‍💻 **Developers**
- **Goal:** Understand the codebase, run locally, make changes
- **Local setup:** [Local Development Guide](./local-dev.md) — run RadiusClaim locally with Dapr sidecars plus the checked-in Redis-backed local components
- **Auth boundaries:** [Authentication Boundaries](./API_AUTHENTICATION.md) — sample endpoint access rules, anonymous approvals, and platform identity notes
- **Product vision:** [Product Requirements Document](./PRD.md) — why RadiusClaim exists, goals, and non-goals
- **Design decisions:** [Architecture Decision Records](./adr/README.md) — rationale behind key technical choices

### 🔐 **Security / API Developers**
- **Sample auth boundaries:** [Authentication Boundaries](./API_AUTHENTICATION.md) — why approvals stay anonymous in this sample
- **Workload Identity:** [Workload Identity Migration](../WORKLOAD_IDENTITY_MIGRATION.md) — platform-layer zero-secret authentication for Azure-backed components

### 🚀 **Advanced Users**
- **Scaling:** [Scaling Boundaries & Mitigation](./SCALING.md) — performance limits and five proven mitigation strategies
- **Observability:** [Observability & Monitoring](./OBSERVABILITY.md) — Jaeger, OpenTelemetry, Application Insights setup
- **Dapr Integration:** [Dapr Component Backfill](./dapr-component-backfill.md) — how Radius recipes project to Dapr component CRDs

---

## The Architecture Story

### The Application Flow

```
Employee submits expense
   ↓
expense-api: POST /expenses
   ↓
workflow-engine: Dapr Workflow (validate, approve/reject, reimburse, notify)
   ↓
notification-svc: Pub/Sub subscriber (sends notifications)
```

### Service Boundaries

- **expense-api:** REST API for expense submission, queries, and manual decision requests
- **workflow-engine:** Dapr Workflow orchestrator (validates, approves, reimburses)
- **notification-svc:** Pub/Sub subscriber (consumes approval/rejection events)

### Dapr Building Blocks Used

- **State:** Persists expenses and workflow state
- **Pub/Sub:** Decouples workflow engine from notification service
- **Workflows:** Orchestrates approval logic with human pauses and timeouts
- **Service Invocation:** Calls between services
- **Secrets:** Stores configuration and platform secrets

---

## Project Structure

```
.
├── src/
│   ├── expense-api/           # REST API service
│   ├── workflow-engine/       # Dapr Workflow orchestrator
│   ├── notification-svc/      # Pub/Sub subscriber
│   └── shared/                # Common utilities
├── infra/
│   ├── radius/                # Radius environment and app definitions
│   │   ├── environments/      # Environment configurations (azure, local)
│   │   ├── recipes/           # Infrastructure recipes (state, pub/sub, secrets)
│   │   └── app.bicep          # Application deployment model
│   └── kubernetes/            # Kubernetes YAML (Dapr components, ingress)
├── scripts/
│   ├── prepare-cluster.sh     # Setup AKS + Dapr + Radius (one time)
│   ├── bootstrap.sh           # Deploy app + validate (repeatable)
│   └── lib/                   # Shared script utilities
├── tests/                     # Test suite
├── docs/                      # Documentation (this directory)
└── README.md                  # Architecture overview
```

---

## Key Concepts

### Dapr (Application Layer)
Keeps your app code portable by abstracting away infrastructure:
- App calls `daprClient.GetStateAsync("expenseIndex")` — doesn't know if it's Redis or PostgreSQL
- App publishes to `pubsub` topic — doesn't know if it's RabbitMQ or Service Bus

### Radius (Infrastructure Layer)
Declares what infrastructure the app needs and where:
- **Environments:** `azure` (cloud) vs. `local` (in-cluster components)
- **Recipes:** Define state stores, pub/sub, secrets for each environment
- **Application model:** `app.bicep` describes Radius resources and Dapr bindings

### Workload Identity (Production)
Zero-secret deployment:
- Service accounts federated to Azure Entra ID via OIDC
- Dapr components authenticate using workload identity tokens
- No secrets stored in Kubernetes

---

## One-Minute Architecture

```
Developer writes code using Dapr APIs
         ↓
         │─ App doesn't know about infrastructure
         │
Radius recipes define infrastructure backing services
         ↓
         │─ Choose recipes per environment (azure, local)
         │─ Dapr components are generated from recipes
         │
Same app code runs locally (kind + Redis) or in cloud (AKS + PostgreSQL)
```

---

## Next Steps

1. **First time?** Run the [Quick Start](#quick-start-deploy-in-2-minutes) above or read the [Deployment Guide](./end-to-end-setup-walkthrough.md).
2. **Want to run locally?** Start with [Local Development Guide](./local-dev.md).
3. **Building the app?** Dive into `src/` — the code is the documentation.
4. **Troubleshooting?** Use the [Validation & Troubleshooting Checklist](./radius-validation-checklist.md).
5. **Securing the API?** Read [API Authentication Guide](./API_AUTHENTICATION.md).

---

## Learn More

- **Dapr:** [dapr.io](https://dapr.io) — official documentation
- **Radius:** [radapp.io](https://radapp.io) — official documentation
- **Bicep:** [microsoft.com/bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview) — IaC language for Radius recipes
- **Kubernetes:** [kubernetes.io](https://kubernetes.io) — container orchestration

---

**Last Updated:** 2026-03  
**Owner:** Eddie (Docs/Story Writer)

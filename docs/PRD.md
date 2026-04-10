# RadiusClaim — Product Requirements Document

> **Version:** 1.0  
> **Date:** 2026-06-06  
> **Author:** Graham (Platform Dev)  
> **Status:** Draft — derived from codebase analysis and team decision history

---

## Executive Summary

RadiusClaim is a reference application that demonstrates how to build portable distributed systems using **Dapr** (application-layer runtime) and **Radius** (infrastructure/environment control plane), deployed on **Kubernetes with Azure backing services**.

The application models an expense-claim workflow: an employee submits an expense, a workflow engine validates and approves (or escalates) it, processes reimbursement, and notifies the employee — all orchestrated through loosely coupled microservices that communicate via Dapr building blocks.

RadiusClaim exists to answer two questions that every platform team faces:

1. **How do I write app code once** and run it locally, in staging, and in production without rewriting for each platform?
2. **How do I declare connections** (state stores, message buses, secrets) cleanly, without littering app code with infrastructure details?

The answer: **Dapr keeps application code portable; Radius declares what the app connects to and where services run.**

---

## Vision & Goals

### Primary Goal
Demonstrate that a non-trivial distributed application can be written once against Dapr abstractions and deployed to any Kubernetes cluster where Radius manages the infrastructure wiring — proving the portability promise with real, running code.

### Secondary Goals
- **Developer education:** Teach platform engineers and app developers how Dapr and Radius work together in a realistic scenario
- **Reference architecture:** Provide a reusable blueprint for distributed workflow applications on Kubernetes
- **CI/CD template:** Show a complete GitHub Actions pipeline that builds, deploys, and validates a Radius + Dapr application end-to-end
- **Zero-secret deployment model:** Demonstrate Azure Workload Identity for Dapr components with no secrets stored in the cluster

### Non-Goals
- **Not production SaaS:** This is a reference sample, not a production-ready expense management system
- **Not multi-tenant:** Single-tenant by design; multi-tenancy patterns are out of scope
- **Not multi-cloud (yet):** Azure backing services are the only implemented recipes; the architecture supports other clouds via recipe substitution but no non-Azure recipes exist today
- **Not a Dapr tutorial:** Assumes basic Dapr familiarity; focuses on the Dapr + Radius integration story
- **Not an ArgoCD/GitOps sample:** Radius is the declarative application model; delivery-pipeline opinions are intentionally excluded (see [Decision: ArgoCD Rejected](/.squad/decisions.md))

---

## Target Users

| Persona | What they get from RadiusClaim |
|---------|-------------------------------|
| **Platform engineers** | See how Radius models an application, wires Dapr components, and manages environment-specific infrastructure via recipes |
| **App developers learning Dapr** | See Dapr Workflows, State, Pub/Sub, and Service Invocation used in a realistic scenario with proper error handling and idempotency |
| **DevOps / SRE teams** | See a repeatable two-phase deployment model (cluster prep → app deploy), idempotent scripts, and CI/CD integration |
| **Architecture evaluators** | Assess the Dapr + Radius separation of concerns for their own platform strategy |

---

## Current State (v0 — What's Built)

### Services

#### expense-api
**Status:** ✅ Fully functional

The public entry point for the application. Accepts expense submissions, persists them via Dapr State, invokes the workflow engine, and serves a lightweight web UI at `/app`.

| Capability | Status | Notes |
|------------|--------|-------|
| POST /expenses/ (submit) | ✅ Working | Idempotent with optimistic concurrency (FirstWrite) |
| GET /expenses/{id} | ✅ Working | Reads from Dapr state store |
| GET /expenses/ (list) | ✅ Working | Bulk-fetches from expense index |
| GET /expenses/{id}/workflow | ✅ Working | Proxies to workflow-engine with graceful degradation |
| GET /app (web UI) | ✅ Working | Static HTML/JS served from wwwroot |
| GET /healthz | ✅ Working | Health check endpoint |
| Dapr error middleware | ✅ Working | Returns 503 when Dapr unavailable |

**Known gaps:** Expense index is unbounded (no pagination or archival). Workflow invocation is fire-and-forget — if the workflow engine is down, the expense is persisted but the workflow never starts.

#### workflow-engine
**Status:** ✅ Fully functional (core flow)

Orchestrates the expense approval lifecycle using Dapr Workflow. Runs activities for approval, reimbursement, and notification publishing.

| Capability | Status | Notes |
|------------|--------|-------|
| POST /workflows/start | ✅ Working | Schedules ExpenseApprovalWorkflow |
| GET /workflows/{instanceId} | ✅ Working | Returns workflow status and progress |
| Auto-approve (< $100) | ✅ Working | Approve → Reimburse → Notify |
| Manual review (≥ $100) | ✅ Working | Route to ManualReviewRequested → Notify |
| Progress tracking | ✅ Working | Custom status breadcrumbs at each step |
| State transitions | ✅ Working | Guard clauses prevent invalid transitions |

**Known gaps:** ManualReviewRequested is a terminal state — no actual manual approval step exists. No rejection workflow implemented. Notification channel is hardcoded to "email".

#### notification-svc
**Status:** ✅ Functional (logging only)

Subscribes to the `expense-notifications` pub/sub topic and logs notifications. Transport implementations (email, SMS, webhooks) are intentionally deferred.

| Capability | Status | Notes |
|------------|--------|-------|
| Pub/Sub subscription | ✅ Working | Receives CloudEvents from Dapr |
| Structured logging | ✅ Working | Logs all notification fields |
| Malformed message handling | ✅ Working | Fail-open: acknowledges bad messages to prevent retry storms |
| Actual notification delivery | ❌ Not implemented | By design — deferred to future phase |

#### Shared Contracts (RadiusClaim.Contracts)
**Status:** ✅ Complete

Defines DTOs, enums, Dapr constants, and event types shared across services:
- `ExpenseRecord`, `ExpenseSubmission`, `NotificationRequest`
- `ExpenseStatus` enum (Submitted, Approved, ManualReviewRequested, Rejected, Reimbursed)
- `NotificationEventType` enum (ExpenseApproved, ExpenseRejected, ManualReviewRequested)
- `RadiusClaimDapr` static constants (app IDs, component names, state keys, topics, workflow names)
- `ExpenseApproved` and `ExpenseRejected` records are defined but **unused** — reserved for future event-sourcing patterns

### Infrastructure

#### Radius Application Model (app.bicep)
**Status:** ✅ Complete

Models three containerized services with Dapr sidecars, three Dapr components (statestore, pubsub, platform-secrets), and a public gateway exposing expense-api. Uses a reusable `container-service.bicep` module. Supports workload identity via pod labels and image pull secrets for private registries.

#### Radius Environments
**Status:** ✅ Complete (two active, one legacy)

| Environment | Target | Status |
|-------------|--------|--------|
| `azure-radius.bicep` | AKS / Arc / self-managed K8s | ✅ Primary — production path |
| `dev.bicep` | Local Kubernetes | ✅ Complete |

#### Radius Recipes (Azure)
**Status:** ✅ Complete

| Recipe | Azure Resource | Auth Model |
|--------|---------------|------------|
| `state-store.bicep` | PostgreSQL Flexible Server (ACID, transactional state for Dapr Actors) | RBAC (Entra admin, PostgreSQL user federation) |
| `pubsub.bicep` | Service Bus Topics (Standard) | RBAC (Azure Service Bus Data Owner) — Entra metadata only, no connection string |
| `secrets.bicep` | Key Vault (Standard, RBAC) | RBAC (Key Vault Secrets User) |

All recipes enforce TLS 1.2, disable public blob access, and support optional RBAC role assignment. All recipes output only Entra metadata — no connection strings or shared keys.

#### Dapr Component Projection
**Status:** ⚠️ Requires post-deploy backfill

Radius recipes provision Azure resources and report metadata, but **do not create Kubernetes Dapr Component CRDs**. The `deploy-dapr-components-workload-identity.sh` script backfills components after `rad deploy`. This is a known Radius platform gap, not a RadiusClaim bug.

#### Workload Identity (Zero Secrets)
**Status:** ✅ Complete (script-level)

All three Dapr components are configured for Azure Workload Identity:
- **statestore** → Storage Blob Data Contributor
- **pubsub** → Azure Service Bus Data Owner
- **platform-secrets** → Key Vault Secrets User

Zero secrets are stored in the cluster. The managed identity `radiusclaim-workload-identity` has federated credentials for all three service accounts.

#### Scripts
**Status:** ✅ Complete and audited

| Script | Purpose | Status |
|--------|---------|--------|
| `prepare-cluster.sh` | First-time AKS/K8s cluster setup (Dapr, Radius, workspace) | ✅ Idempotent |
| `bootstrap.sh` | Repeatable app deployment (recipes, environment, app, components, validation) | ✅ Idempotent |
| `teardown.sh` | Clean up Azure resources, Radius artifacts, GHCR packages | ✅ Safe (AKS preserved unless flagged) |
| `deploy-dapr-components-workload-identity.sh` | Backfill Dapr CRDs with Azure Workload Identity (OIDC federated credentials, no secrets in cluster) | ✅ Primary |
| `deploy-dapr-components.sh` | Legacy backfill (service principal auth, deprecated — do not use) | ⚠️ Deprecated |
| `publish-radius-recipes.sh` | Publish recipes as OCI artifacts to GHCR | ✅ Complete |
| `validate-deployment.sh` | End-to-end smoke test ($50 auto-approve, $150 manual review) | ✅ Complete |

All scripts pass `bash -n` syntax check. Eight audit findings from Pete's review have been remediated.

#### CI/CD Pipeline
**Status:** ✅ Complete

`.github/workflows/deploy-azure.yml` runs on push to `main`:
1. Validate (.NET build, Bicep parse)
2. Build and push container images to GHCR
3. Publish recipes to GHCR
4. Configure Radius workspace and register Azure credentials
5. Deploy environment and application via `rad deploy`
6. Validate Kubernetes wiring (pods, sidecars, Dapr components)
7. End-to-end smoke test (health check, $50 auto-approve, $150 manual review, notification log verification)

#### Local Development
**Status:** ✅ Functional (Redis-backed)

`infra/dapr/local/` provides Docker Compose for Redis and local Dapr component overlays (state.redis, pubsub.redis). Services run via `dapr run` with local component files. No Radius recipes exist for local — the local path uses Dapr components directly.

---

## Functional Requirements

### FR-1: Expense Submission
**Status:** ✅ Implemented

An employee submits an expense with employee ID, amount, currency, and description. The system persists the expense, assigns a unique ID and correlation ID, and triggers the approval workflow.

**Acceptance criteria:**
- POST /expenses/ validates input (non-empty fields, amount > 0)
- Duplicate submissions with matching IDs return the existing record (idempotent)
- Conflicting submissions with different data return 409 Conflict
- Expense state is persisted before workflow invocation
- Currency is normalized to uppercase

### FR-2: Expense Approval Workflow
**Status:** ✅ Implemented (auto-approve path only)

A Dapr Workflow orchestrates the approval lifecycle:
- Expenses under $100 are auto-approved, reimbursed, and notification is sent
- Expenses $100 or above are routed to ManualReviewRequested and notification is sent

**Acceptance criteria:**
- $50 expense → Approved → Reimbursed → Notification published ✅
- $150 expense → ManualReviewRequested → Notification published ✅
- Workflow progress is queryable via GET /workflows/{instanceId} ✅
- State transitions are guarded (cannot re-approve an already-reimbursed expense) ✅

**Not yet implemented:**
- Manual approval/rejection step for escalated expenses
- Configurable approval threshold
- Rejection workflow (ExpenseRejected event type defined in contracts but unused)

### FR-3: Notification Delivery
**Status:** ⚠️ Partially implemented (logging only)

Workflow publishes notification events to Dapr pub/sub. The notification service subscribes and logs them.

**Acceptance criteria:**
- Notification event contains expense ID, correlation ID, recipient, subject, message ✅
- Notification service receives and acknowledges events ✅
- Malformed messages are logged and acknowledged (no retry storms) ✅
- Actual delivery via email/SMS/webhook ❌ (deferred)

### FR-4: State Management (Dapr)
**Status:** ✅ Implemented

All state operations use Dapr State Store abstraction:
- Expense records keyed by `expense:{id}`
- Expense index maintained for listing
- Workflow activities read/update state with concurrency guards
- State store component is pluggable (Redis locally, PostgreSQL in production for ACID transactional state)

### FR-5: Infrastructure Portability (Radius)
**Status:** ✅ Implemented

Radius models the application topology, Dapr component wiring, and environment-specific infrastructure:
- `app.bicep` defines services, connections, and gateway — cloud-agnostic
- `azure-radius.bicep` binds recipes that provision Azure backing services
- `dev.bicep` targets local Kubernetes
- Recipes are published as OCI artifacts and resolved at deploy time

**Not yet implemented:**
- Local Radius recipes (Redis-backed) for full local-dev parity via Radius
- Non-Azure recipes (AWS, GCP) for multi-cloud demonstration

### FR-6: Local Development Experience
**Status:** ✅ Functional (Dapr-direct)

Developers can run services locally with `dapr run` using Redis-backed components defined in `infra/dapr/local/`. Docker Compose provides the Redis instance.

**Gap:** Local development bypasses Radius entirely. There are no local Radius recipes, so the "Radius manages everything" story only applies to cluster deployments.

### FR-7: CI/CD Pipeline
**Status:** ✅ Implemented

GitHub Actions workflow builds, deploys, and validates on every push to `main`. Includes Bicep validation, image publishing, recipe publishing, Radius deployment, and end-to-end smoke testing.

### FR-8: Zero-Secret Deployment
**Status:** ✅ Implemented

Azure Workload Identity provides pod-level authentication for all Dapr components. No secrets (connection strings, account keys, client secrets) are stored in the cluster. RBAC grants are scoped per Azure resource.

### FR-9: Deployment Lifecycle Management
**Status:** ✅ Implemented

Two-phase operator model:
1. `prepare-cluster.sh` — one-time cluster setup (AKS, Dapr, Radius control planes)
2. `bootstrap.sh` — repeatable application deployment with full preflight validation

Both scripts are idempotent and re-runnable. `teardown.sh` provides controlled cleanup with explicit opt-in for destructive actions.

---

## Non-Functional Requirements

### Portability
- Application code uses only Dapr abstractions — no Azure SDK calls in business logic
- Radius app model (`app.bicep`) is cloud-agnostic; environment Bicep binds cloud-specific recipes
- Same .NET code runs locally with Redis and on AKS with Azure services
- Deployment targets: AKS, Arc-enabled Kubernetes, self-managed Kubernetes

### Zero Secrets in Code
- Workload identity for all Dapr components (statestore, pubsub, secrets)
- Service principal registration for Radius control plane (credential stored in Radius, not in application namespace)
- No `AZURE_CLIENT_SECRET` required in pod environment
- RBAC grants are per-resource, least-privilege

### Idempotency
- `bootstrap.sh` and `teardown.sh` are re-runnable without side effects
- Expense submission is idempotent (duplicate detection via correlation ID)
- Radius deployment uses `rad deploy` with in-place updates
- Workflow start is idempotent (checks for existing instance)

### Observability
- Dapr Workflow progress tracking via custom status breadcrumbs
- Structured logging across all services
- Workflow telemetry queryable via expense-api proxy endpoint
- Dapr sidecar health visible via pod readiness (2/2 containers)

### Consistency Model
- State store operations use optimistic concurrency (FirstWrite)
- Expense index updates retry with backoff on conflict
- Workflow state transitions are guarded by status checks

### Radius Version Alignment
- Targets Radius 0.55 stable API surface (`Applications.Core/*`, `Applications.Dapr/*`)
- Avoids preview `Radius.Compute/*` namespace (documented pivot path for future releases)
- Recipe OCI artifacts published to GHCR with version tags

---

## System Architecture

### Services and Data Flow

```
Employee / Browser
       │
       ▼
┌─────────────────┐
│  Radius Gateway  │  (public HTTPS endpoint)
│  /app, /expenses │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     Dapr Service        ┌──────────────────┐
│   expense-api    │────Invocation──────────▶│  workflow-engine  │
│  (Minimal API)   │                         │  (Dapr Workflow)  │
│                  │                         │                   │
│  State: R/W      │                         │  State: R/W       │
│  Secrets: Read   │                         │  PubSub: Publish  │
└────────┬─────────┘                         │  Secrets: Read    │
         │                                   └────────┬──────────┘
         │                                            │
         │                                   Dapr Pub/Sub
         │                                   (expense-notifications)
         │                                            │
         │                                            ▼
         │                                   ┌──────────────────┐
         │                                   │ notification-svc  │
         │                                   │ (Subscriber)      │
         │                                   │                   │
         │                                   │ PubSub: Subscribe │
         │                                   │ Secrets: Read     │
         │                                   └──────────────────┘
         │
    Dapr Building Blocks
         │
    ┌────┴─────────────────────────────────┐
    │                                      │
    ▼              ▼                ▼
┌─────────┐  ┌──────────┐  ┌──────────────┐
│  State   │  │  PubSub  │  │   Secrets    │
│  Store   │  │  Broker  │  │   Store      │
│          │  │          │  │              │
│ Local:   │  │ Local:   │  │ Azure:       │
│  Redis   │  │  Redis   │  │  Key Vault   │
│ Azure:   │  │ Azure:   │  │              │
│  Blob    │  │  Service │  │              │
│  Storage │  │  Bus     │  │              │
└─────────┘  └──────────┘  └──────────────┘
```

### Dapr Building Blocks in Use

| Building Block | Component Name | Local Backend | Azure Backend |
|----------------|---------------|---------------|---------------|
| State Store | `statestore` | Redis (state.redis v1) | PostgreSQL (state.postgresql v2, transactional for Dapr Actors) |
| Pub/Sub | `pubsub` | Redis (pubsub.redis v1) | Azure Service Bus Topics (pubsub.azure.servicebus.topics v1) |
| Secret Store | `platform-secrets` | — | Azure Key Vault (secretstores.azure.keyvault v1) |
| Workflows | (built-in) | Dapr runtime | Dapr runtime |
| Service Invocation | (built-in) | Dapr runtime | Dapr runtime |

### Radius Resources

| Resource Type | Name | Purpose |
|--------------|------|---------|
| `Applications.Core/applications` | `radiusclaim` | Application scope |
| `Applications.Core/containers` | `expense-api`, `workflow-engine`, `notification-svc` | Service deployment with Dapr sidecars |
| `Applications.Core/gateways` | `expense-gateway` | Public HTTP endpoint for expense-api |
| `Applications.Dapr/stateStores` | `statestore` | Backed by recipe: PostgreSQL Flexible Server (transactional state for Dapr Actors) |
| `Applications.Dapr/pubSubBrokers` | `pubsub` | Backed by recipe: Azure Service Bus |
| `Applications.Dapr/secretStores` | `platform-secrets` | Backed by recipe: Azure Key Vault |

### Deployment Topology

```
Phase 1: Cluster Preparation (one-time)
  prepare-cluster.sh
    → Create/verify AKS cluster
    → Install Dapr control plane (dapr init -k --wait)
    → Install Radius control plane (rad install kubernetes)
    → Configure Radius workspace and resource group

Phase 2: Application Deployment (repeatable)
  bootstrap.sh
    → Preflight validation (CLIs, Azure auth, K8s health, Dapr/Radius ready)
    → Publish recipes as OCI artifacts to GHCR
    → Deploy Radius environment (azure-radius.bicep → provisions Azure resources)
    → Deploy Radius application (app.bicep → creates containers + Dapr wiring)
    → Backfill Dapr Component CRDs (workload identity)
    → Run end-to-end validation
```

---

## Outstanding Work (Backlog)

### High Priority

**[HIGH] Manual Approval Step for Escalated Expenses**  
The workflow routes expenses ≥ $100 to `ManualReviewRequested` but this is a terminal state. No API endpoint or mechanism exists for a manager to approve or reject the expense. This is the most visible functional gap — the demo tells a half-story for large expenses. Requires: new API endpoint on workflow-engine (e.g., `POST /workflows/{id}/decide`), a new workflow activity to wait for external input, and UI support.

**[HIGH] Dapr Component CRD Auto-Projection**  
Radius recipes provision Azure resources but do not create Kubernetes Dapr Component CRDs. The `deploy-dapr-components-workload-identity.sh` script fills this gap, but it means the deployment is not fully declarative through Radius alone. This is partly a Radius platform limitation, but RadiusClaim should track and adopt any upstream fix. In the meantime, the bootstrap script automates the backfill transparently.

**[CLOSED] Pubsub Recipe Workload Identity Migration**  
The `pubsub.bicep` recipe now outputs only Entra metadata (namespace endpoint, topic name) and assigns `Azure Service Bus Data Owner` RBAC — matching the zero-secret pattern established by `state-store.bicep`. No connection string is output. The zero-secret recipe layer is complete.

**[HIGH] Automated Integration Tests**  
No test suite exists beyond the CI smoke test (`validate-deployment.sh`). A proper test harness should cover: unit tests for approval logic, integration tests for Dapr workflow execution, and contract tests for inter-service communication. Phase 1 validation explicitly deferred this, but it's required for a complete reference app.

**[HIGH] Phase 7 Validation Sign-Off**  
The phase-7-validation-checklist.md has unchecked exit criteria and no approval signature from Karen (Tester). Completing this sign-off gates the project's claim of "demo-ready."

### Medium Priority

**[MEDIUM] Local Radius Recipes (Redis-Backed)**  
Local development uses Dapr component overlays directly, bypassing Radius. Creating local recipes (`infra/radius/recipes/local/`) that provision Redis-backed components through Radius would demonstrate full portability: same `app.bicep`, different environment, different recipes. Identified as a gap in Daisy's portability audit.

**[MEDIUM] Configurable Approval Threshold** ✅ *Implemented — Issue #7*  
The auto-approve threshold is configurable via `APPROVAL_THRESHOLD_USD` env var (default: 100.0). Set in `appsettings.json` under `ApprovalThreshold:ThresholdUsd`; override via env var for zero-code-change deployments.

**[MEDIUM] Expense Rejection Workflow**  
`ExpenseRejected` event type and `ExpenseStatus.Rejected` are defined in contracts but never generated. Implementing the rejection path would complete the workflow lifecycle and make the notification-svc more interesting (different notification content per outcome).

**[CLOSED] Radius Validation Checklist Update for Workload Identity**  
✅ Completed. All docs have been updated to reflect workload identity as the default and only supported auth model. Shared-key and service principal auth references have been removed or marked as deprecated. Prerequisites and troubleshooting sections now clearly document workload identity flow.

**[MEDIUM] Expense Index Pagination and Archival**  
The expense index (`expense-index` key) grows unboundedly. For a reference app, this should demonstrate a sensible approach: pagination on the list API, and optionally an archival strategy for old entries.

### Low Priority

**[LOW] Notification Transport Implementation**  
Replace logging-only notifications with actual delivery (email via SendGrid, Slack webhook, etc.). This has been explicitly deferred but would complete the end-to-end story for demos that want to show real-world integration.

**[LOW] Multi-Cloud Recipes**  
Create recipes for AWS (S3 + SNS/SQS + Secrets Manager) or GCP equivalents to demonstrate the portability promise beyond Azure. The architecture supports this — it's a recipe-authoring exercise, not an app change.

**[LOW] Notification Template System**  
Notification subjects and messages are hardcoded in workflow activities. A template system (even a simple key-value lookup from Dapr secrets) would make the notification-svc more realistic.

**[LOW] Workflow Monitoring Dashboard**  
No observability dashboard exists. Adding Dapr metrics export and a basic Grafana dashboard would demonstrate the observability story that platform teams expect.

**[LOW] GHCR Image Pull Secret Conditionality**  
The GHCR pull secret is always injected into pod specs. It should be conditional on whether the container registry requires authentication (public vs. private GHCR packages). Identified in Daisy's portability audit as a minor concern.

---

## Success Criteria

RadiusClaim is "done" as a reference app when:

1. **End-to-end demo works reliably:** A platform engineer can clone the repo, run two scripts (`prepare-cluster.sh` + `bootstrap.sh`), and have a working expense workflow in under 30 minutes — including submitting expenses via the web UI and seeing notifications in logs.

2. **Both approval paths are complete:** Auto-approve (< $100) runs to reimbursement; manual review (≥ $100) includes a mechanism for human decision that resolves the workflow.

3. **Zero secrets, zero manual steps:** Workload identity is the default auth path. No `AZURE_CLIENT_SECRET` in the cluster. No manual `kubectl apply` steps outside the scripted path.

4. **CI passes on every push:** The GitHub Actions pipeline builds, deploys, and validates the full workflow including notification delivery verification.

5. **Tests exist:** Unit tests for approval logic, integration tests for the workflow lifecycle, and the existing smoke test for end-to-end validation.

6. **Docs are current:** README, walkthrough, and validation checklist all reflect the actual deployment experience. A new contributor can understand the architecture, deploy it, and modify it without tribal knowledge.

7. **Local and cloud parity:** `dapr run` locally and `rad deploy` to AKS use the same app code, same Dapr abstractions, and (ideally) the same Radius app model with different environment bindings.

---

## Appendix: Key Decisions

Decisions are maintained in `.squad/decisions.md`. The following are the most architecturally significant:

| Date | Decision | Status | Impact |
|------|----------|--------|--------|
| 2026-03-24 | **Kubernetes-First Deployment** (ADR-0001) | Implemented | Radius + K8s is the primary deployment path |
| 2026-03-25 | **State-Store Auth Pivot to Microsoft Entra** | Implemented | Shared-key auth blocked by tenant policy; all recipes use RBAC |
| 2026-03-25 | **Cluster Prep Separated from App Deployment** | Implemented | `prepare-cluster.sh` (one-time) vs. `bootstrap.sh` (repeatable) |
| 2026-03-25 | **Bootstrap Default Location: belgiumcentral** | Implemented | Aligns script defaults with operator walkthrough guidance |
| 2026-03-26 | **Dapr Component Projection Gap Diagnosed** | Diagnosed | Radius doesn't project CRDs; backfill script is the workaround |
| 2026-03-26 | **Azure Workload Identity for Dapr** | Implemented | Zero secrets in cluster; managed identity with federated credentials |
| 2026-03-26 | **ArgoCD Rejected for RadiusClaim** | Rejected | Adds complexity without teaching value; Radius is the app model |
| 2026-03-26 | **GHCR Recipe Publish Auth** | Implemented | Explicit credentials for CI and manual publishing |
| 2026-03-27 | **Service Bus Zero-Secret Migration** | Implemented (script) | Pubsub component uses workload identity; connection string eliminated at runtime |
| 2026-06-05 | **Script Audit Remediation (8 findings)** | Implemented | All scripts pass syntax check; deprecated scripts marked |
| 2026-06-05 | **SPN Role Assignment Idempotency** | Implemented | Reused SPNs get Contributor role verified/assigned |

---

## Appendix: Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Runtime | .NET | 10.0 |
| Framework | ASP.NET Core Minimal API | 10.0 |
| Dapr SDK | Dapr.AspNetCore, Dapr.Workflow | 1.17.5 |
| Infrastructure as Code | Bicep (Radius extensions) | Radius 0.55 |
| Container Registry | GitHub Container Registry (GHCR) | — |
| CI/CD | GitHub Actions | — |
| Kubernetes | AKS (primary), any K8s with Dapr + Radius | — |
| State Store | PostgreSQL (prod, transactional for Dapr Actors), Redis (local) | — |
| Message Bus | Azure Service Bus Topics (prod), Redis (local) | — |
| Secret Store | Azure Key Vault (prod) | — |
| Identity | Azure Workload Identity | — |

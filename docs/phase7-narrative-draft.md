# Phase 7: Radius-First Narrative & Demo Walkthrough

> **Status:** Draft for Karen and Daisy review  
> **Target:** README finalization + demo script flow  
> **Dependencies:** Pending Entra auth details from Graham (marked with `[ENTRA_AUTH_DETAILS_PENDING]`)

---

## Section 1: Radius-First Narrative

### What This Sample Demonstrates

**RadiusClaim is a reference sample showing how to write **portable** distributed applications using Dapr and Radius.**

- **App code** written once, deploys anywhere via **Dapr abstractions** (state, pub/sub, workflows, service invocation)
- **Infrastructure** declared once, adapts across environments via **Radius environment + recipe patterns** (local, dev, production)
- **Deployment** runs on any Kubernetes cluster with optional Azure backing services

The challenge: **Teams want to build once and deploy anywhere, but infrastructure choices are real.** Dapr handles app portability. Radius handles infrastructure clarity.

---

### What Dapr Owns: App Portability

Dapr provides **building blocks** that abstract away cloud provider specifics. RadiusClaim's application code depends on these blocks exclusively:

| Building Block | What It Does | RadiusClaim Use |
|---|---|---|
| **State** | Persist and retrieve key-value data | Store expenses, workflow checkpoints, query history |
| **Pub/Sub** | Publish events, subscribe to topics | Workflow publishes `ExpenseApproved`/`ExpenseRejected`; notification-svc subscribes |
| **Workflows** | Orchestrate multi-step activities with state checkpoints | Validate → approve/reject → process reimbursement |
| **Service Invocation** | Call other services by name without HTTP details | expense-api invokes workflow-engine through Dapr |

**Portability guarantee:** The same C# code runs:
- **Locally** with Redis (state), RabbitMQ (pub/sub)
- **On Kubernetes** with any Dapr backing component (Azure Blob, Service Bus, etc.)
- **Across clouds** if recipes exist for that cloud

The app is **cloud-agnostic** — it doesn't know if it's hitting Azure Blob or another object store. Dapr abstracts the details.

---

### What Radius Owns: Infrastructure Definition & Wiring

Dapr keeps apps portable. **Radius keeps infrastructure sane.** Platform engineers use Radius to:

| Responsibility | How Radius Helps | RadiusClaim Example |
|---|---|---|
| **Define workloads** | Declare containers, resources, topology | expense-api, workflow-engine, notification-svc |
| **Wire connections** | Link workloads to backing services | Connect expense-api → state store via `link` |
| **Manage environments** | Switch backing services without redeploying app | Local env uses Redis; Azure env uses Blob |
| **Handle auth** | Generate and inject credentials, manage RBAC | Service principals, workload identity assignments |
| **Expose services** | Manage public endpoints, ingress | Radius gateway routes `/app` to expense-api |

**How it works:**

1. **Recipes** are templates that provision backing services (Azure Blob, Service Bus, etc.)
2. **Environments** stitch recipes together into a coherent infrastructure definition
3. **Application model** declares what it needs; Radius wires it all together

```bicep
// Application declares generic need
resource statestore 'Applications.Dapr/stateStores@2023-10-01-preview' = {
  name: 'statestore'
  properties: {
    environment: environment
    application: app.name
    type: 'state.azure.blobstorage'
  }
}

// Environment chooses the Recipe
recipes: {
  'Applications.Dapr/stateStores': {
    default: {
      templatePath: 'ghcr.io/wesback/radiusclaim/recipes/state-store:latest'
    }
  }
}

// Recipe provisions the actual Azure Blob Storage and wires auth
// → Radius generates Dapr component CRD with correct credentials
// → Dapr component backfill projects the CRD into Kubernetes
// → App code calls Dapr State API — zero awareness of Azure
```

---

### The Three Deployment Paths

This sample demonstrates **Radius portability in action** across three deployment scenarios:

#### **Path 1: Local Kubernetes (Development)**
- **What:** Single-machine Kubernetes (Docker Desktop, Minikube, kind)
- **Backing services:** In-cluster Redis, RabbitMQ (deployed via Recipes)
- **Use case:** Rapid iteration, no Azure subscription needed
- **Command:**
  ```bash
  rad deploy infra/radius/environments/local.bicep
  ```

#### **Path 2: Kubernetes + Radius + Azure Services (Development or Staging)**
- **What:** Self-managed or AKS cluster, Radius control plane, Azure-backed services
- **Backing services:** Azure Blob Storage, Azure Service Bus, Azure Key Vault
- **Use case:** Development with production-equivalent services; catch integration issues early
- **Command:**
  ```bash
  rad deploy infra/radius/environments/dev.bicep \
    --parameters azureSubscriptionId=<sub-id> \
    --parameters azureResourceGroup=<rg-name>
  ```

#### **Path 3: Azure Kubernetes Service (AKS) + Radius + Azure Services (Production)**
- **What:** Managed Kubernetes cluster (AKS), Radius control plane, production Azure services
- **Backing services:** Production-hardened Blob Storage, Service Bus, Key Vault (RBAC, workload identity)
- **Use case:** Production deployments with managed Kubernetes reliability
- **Command:**
  ```bash
  rad deploy infra/radius/environments/azure-radius.bicep \
    --parameters "@infra/radius/environments/azure-radius.parameters.json" \
    --parameters azureSubscriptionId=<sub-id> \
    --parameters azureResourceGroup=<rg-name>
  ```

**Key insight:** All three paths run the **identical application code**. Only the environment's Recipe choices change.

---

## Section 2: Step-by-Step Demo Walkthrough (10 Minutes)

### Demo Scenario

A financial services company needs to demonstrate expense reimbursement to stakeholders. This walkthrough shows:

1. **Employee submission** → System captures the expense
2. **Auto-approval** → Workflow validates and approves amounts under $100
3. **Notification** → Approval event triggers a notification
4. **Query** → User retrieves expense history

**Total flow time:** ~2–3 seconds from submit to approved state.

---

### Prerequisites

- RadiusClaim deployed (locally, on K8s, or on AKS)
- Web UI accessible at `http://<endpoint>/app` (or via `kubectl port-forward`)
- Dapr sidecars healthy on expense-api, workflow-engine, and notification-svc pods
- State store and pub/sub components ready (check with `rad resource list`)

---

### Demo Steps

#### **Step 1: Open the Web UI (30 seconds)**

Navigate to the expense-api web interface:

```
http://localhost:5000/app  (local port-forward)
— or —
https://<radius-gateway-endpoint>/app  (Kubernetes public endpoint)
```

The page shows:
- **Submit Expense** form (employee ID, amount, description)
- **Recent Expenses** table (live-updating list)

**Demo note:** Point out that this UI is **part of the app**, not a separate deployment. No Node toolchain, no CORS setup—just ASP.NET serving static HTML. Reduces cognitive load: "The app is the app."

---

#### **Step 2: Submit a Small Expense ($50) (45 seconds)**

Fill in the form:

- **Employee ID:** `emp-001`
- **Amount:** `50`
- **Currency:** `USD`
- **Description:** `Client lunch meeting`

Click **Submit**.

**What happens:**
1. expense-api receives POST, generates `ExpenseId` and `CorrelationId`
2. Writes to state store (Dapr State API)
3. Invokes workflow-engine via Dapr Service Invocation
4. workflow-engine starts orchestration

**Demo visual:** The form clears, and you see a **toast notification** (or console log): "Expense submitted (ID: [uuid])".

**Narration:** "The API doesn't store anything in its own database. It uses Dapr State, so the same code works with Redis locally, Blob Storage in Azure, or any other Dapr-compatible state store."

---

#### **Step 3: Watch Auto-Approval in Real Time (30 seconds)**

The workflow-engine orchestrates in real time:

1. **ValidateExpense activity** → Checks business rules (amount, required fields)
2. **ApproveExpense activity** → Auto-approves if amount < $100
3. **ProcessReimbursement activity** → Marks expense as approved, schedules payout
4. **Publish `ExpenseApproved` event** → Sends event to pub/sub topic

**Expected outcome:** Within 2–3 seconds, the **Recent Expenses** table updates:

```
Expense ID        | Employee | Amount | Status   | Approved At
abc-123-def-456   | emp-001  | $50    | Approved | 2026-03-26 10:30:45 UTC
```

**Demo visual:** Refresh the page or use live WebSocket updates (if configured) to show the table updating without manual refresh.

**Narration:** "The workflow is a **saga**—multi-step orchestration with built-in state checkpoints. If the system crashed mid-workflow, it would resume from the last checkpoint. That's what Dapr Workflows gives us."

---

#### **Step 4: Verify Notification Delivery (30 seconds)**

The notification-svc has subscribed to the pub/sub topic and received the `ExpenseApproved` event.

**Where to see it:**
- **Local dev:** Check the notification-svc console log:
  ```
  [INFO] Notification received: Expense emp-001 for $50 approved
  ```
- **Kubernetes:** Tail the notification-svc pod:
  ```bash
  kubectl logs -f deployment/notification-svc -c notification-svc \
    -n radiusclaim-azure-radiusclaim
  ```
- **Demo simplification:** If you're on a large cluster, use `kubectl port-forward` to bring logs to a terminal pane visible on the demo screen.

**Narration:** "The workflow doesn't care who handles the approval event. It publishes to a topic; the notification service subscribes. If we added a **SMS gateway** or **Slack integration**, we'd just add another subscriber. The workflow code doesn't change."

---

#### **Step 5: Submit a Large Expense ($500) and Watch Rejection (60 seconds)**

Fill in the form again:

- **Employee ID:** `emp-002`
- **Amount:** `500`
- **Currency:** `USD`
- **Description:** `Vendor conference registration`

Click **Submit**.

**What happens:**
1. expense-api submits to workflow-engine
2. ValidateExpense passes
3. **ApproveExpense checks:** $500 > $100, so it **rejects** with reason "Amount exceeds limit; escalate to manager"
4. Publish `ExpenseRejected` event

**Expected outcome:** Recent Expenses table shows:

```
Expense ID        | Employee | Amount | Status   | Reason
def-789-ghi-012   | emp-002  | $500   | Rejected | Amount exceeds limit; escalate to manager
```

**Narration:** "The workflow is **deterministic**—same logic, same decision every time. But notice: the code doesn't have hardcoded approval limits or rejection reasons. Those can be externalized to a config service or moved to a manager approval queue in a later iteration. The pattern stays the same."

---

#### **Step 6: Query Expense History (60 seconds)**

Use the web UI or a direct API call to retrieve all expenses:

```bash
curl -X GET https://<endpoint>/api/expenses \
  -H "Content-Type: application/json"
```

**Expected output:**

```json
[
  {
    "id": "abc-123-def-456",
    "employeeId": "emp-001",
    "amount": 50.0,
    "currency": "USD",
    "status": "Approved",
    "approvedAt": "2026-03-26T10:30:45Z"
  },
  {
    "id": "def-789-ghi-012",
    "employeeId": "emp-002",
    "amount": 500.0,
    "currency": "USD",
    "status": "Rejected",
    "rejectionReason": "Amount exceeds limit; escalate to manager",
    "rejectedAt": "2026-03-26T10:31:02Z"
  }
]
```

**Demo insight:** Point out the **correlation IDs** in workflow logs and notification headers—these tie the entire flow together for troubleshooting.

**Narration:** "Every expense in the system has a workflow instance ID and correlation ID. If you need to debug, you can trace the entire journey: submission → validation → decision → notification. That's what distributed tracing in Dapr gives you out of the box."

---

### End-of-Demo Talking Points

After the walkthrough, tie it back to the Radius + Dapr split:

1. **The code you just saw** is 100% portable—it would run the same way on any Kubernetes cluster with Dapr, any public cloud with Radius recipes, or even a self-managed data center.

2. **The infrastructure** (Blob Storage, Service Bus, Key Vault) is provided by **Radius recipes**. Change the environment, and the same app wires to different backing services automatically.

3. **No shared keys, no hardcoded credentials.** Workload identity handles everything—the app never sees secrets.

4. **This pattern scales.** Add a new backing service (e.g., a vector database for expense analytics)? Write a Radius recipe once, link it in the app model, and every environment gets it automatically.

---

## Section 3: Authentication Model

### The Problem: Shared-Key Auth is Blocked

The Azure tenant running this sample **disallows shared-key authentication** on storage accounts (`allowSharedKeyAccess: false`). This breaks the old auth pattern:

```bicep
// ❌ OLD APPROACH (now blocked by Azure Policy)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-06-01' = {
  // ...
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: true  // ← Policy denial
  }
}

// Dapr component would use accountKey
resource statestore 'Applications.Dapr/stateStores@2023-10-01-preview' = {
  properties: {
    component: {
      auth: [
        {
          name: 'accountKey'
          secretRef: 'storagekey'
        }
      ]
    }
  }
}
```

**Impact:**
- `scripts/bootstrap.sh` fails on the shared-key readiness check
- Dapr component projection fails: `KeyBasedAuthenticationNotPermitted`
- Production audit logs flag the weak authentication pattern

**Solution:** Migrate to **Microsoft Entra workload identity**.

---

### The New Pattern: Microsoft Entra + Workload Identity

[ENTRA_AUTH_DETAILS_PENDING]

**High-level flow** (Graham to fill in technical details):

1. **Workload Identity Setup**
   - Service account created in Kubernetes with Dapr workload annotations
   - Azure Workload Identity OIDC provider configured
   - Trust relationship established between K8s SA and Azure AD application

2. **Recipe-Driven RBAC**
   - Radius recipe provisions the Azure storage account **without** shared keys
   - Recipe creates Azure AD service principal (or managed identity)
   - Recipe assigns `Storage Blob Data Contributor` role to the service principal
   - Recipe outputs workload identity metadata (e.g., client ID, tenant ID)

3. **Dapr Component Projection**
   - `deploy-dapr-components-workload-identity.sh` (or backfill script) generates Dapr Component CRD
   - Component uses **Azure AD authentication**, not `accountKey`
   - Dapr sidecar reads Kubernetes SA token, exchanges it for Azure AD token via OIDC
   - Dapr connects to Blob Storage using federated identity

4. **App Code: No Changes**
   - Application still calls `daprClient.GetStateAsync("statestore", key)`
   - Dapr handles the full auth dance invisibly
   - No secrets in environment variables, no key rotation burden

---

### Why This Matters for Production

| Concern | Shared-Key Auth | Workload Identity |
|---|---|---|
| **Compliance** | Violates org policies, audit red flag | ✅ Zero Trust, RBAC enforced |
| **Key Rotation** | Manual or scripted, complex | ✅ Automatic token refresh, OS-managed |
| **Audit Trail** | Limited—logs show shared-key access | ✅ Full AAD audit trail, service principal visibility |
| **Security Boundary** | Shared key = access to entire storage account | ✅ RBAC scope limits blast radius |
| **Portability** | Azure-only | ✅ OIDC pattern works across clouds |

---

### Deployment Walkthrough with Entra Auth

[ENTRA_AUTH_DETAILS_PENDING]

**Bootstrap flow** (Graham to fill in exact steps):

1. `bootstrap.sh` pre-flight checks Entra readiness
2. Recipe provisions Blob + managed identity + RBAC
3. `deploy-dapr-components-workload-identity.sh` generates component CRD with Entra metadata
4. Dapr control plane injects sidecar with correct OIDC configuration
5. First expense submission: sidecar auto-exchanges K8s SA token for Azure AD token
6. Dapr calls Blob Storage using federated identity ✅

---

### Configuration Example

[ENTRA_AUTH_DETAILS_PENDING]

**Expected Dapr component after recipe + backfill:**

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: radiusclaim-azure-radiusclaim
spec:
  type: state.azure.blobstorage
  version: v1
  auth:
    secretStore: kubernetes  # Or Azure Key Vault if needed
  metadata:
    - name: accountName
      value: <generated-storage-account-name>
    - name: containerName
      value: radiusclaim-state
    - name: azureTenantId
      value: <tenant-id>
    - name: azureClientId
      value: <managed-identity-client-id>
    - name: azureClientSecret
      secretKeyRef:
        name: ""  # Empty = use Workload Identity OIDC
        key: ""
  scopes:
    - expense-api
    - workflow-engine
```

**Key points:**
- `azureClientSecret` is empty (triggers workload identity path)
- Dapr sidecar reads K8s SA token from `/var/run/secrets/tokens/vault-token`
- OIDC endpoint exchanges token for Azure AD token automatically

---

### Troubleshooting Entra Auth Failures

[ENTRA_AUTH_DETAILS_PENDING]

If Dapr sidecars crash with "Entra auth failed," check:

1. **Managed identity has `Storage Blob Data Contributor` on the storage account**
   ```bash
   az role assignment list \
     --assignee <managed-identity-object-id> \
     --scope <storage-account-id> \
     --query "[].roleDefinitionName"
   ```

2. **OIDC provider is configured and service account is annotated**
   ```bash
   kubectl get sa <service-account-name> -n radiusclaim-azure-radiusclaim -o yaml \
     | grep workload.identity.azure.com
   ```

3. **Dapr component references correct tenant, client ID, and storage account**
   ```bash
   kubectl get component statestore -n radiusclaim-azure-radiusclaim -o yaml
   ```

---

## Summary for Review

This draft covers:

1. **Radius-first narrative** — explains what Dapr and Radius own, demonstrates three deployment paths
2. **Demo walkthrough** — 10-minute flow from submission to query, with talking points
3. **Authentication model** — old (blocked) pattern, new (Entra) pattern, why it matters, troubleshooting

**Sections marked `[ENTRA_AUTH_DETAILS_PENDING]`** await Graham's final Entra recipe design. Once Graham lands the recipe changes, those sections can be filled in with:
- Exact bootstrap commands
- Sample Dapr component YAML
- OIDC configuration details
- Specific workload identity annotations

**Next steps for Karen and Daisy:**
- Review narrative for clarity and audience fit
- Check demo walkthrough against actual UI/API behavior
- Validate auth section makes sense without Graham's final code
- Suggest any missing elements before we finalize and merge into README


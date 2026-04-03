# Phase 7 Validation Scenarios

> **Owner:** Karen (Tester)  
> **Phase:** 7 — End-to-End Radius Validation, Integration Tests, Release Readiness  
> **Updated:** 2026-03-27  
> **Status:** Scenario Design Document (prerequisites, happy paths, edge cases, gates, live checklist)

---

## Purpose

This document **designs the complete test matrix for Phase 7 release validation**. It covers:

1. **Happy Path Scenarios** — baseline credibility for the demo story
2. **Edge Cases & Failure Paths** — where the system is stressed or broken
3. **Regression Gates** — assurance that Phases 1–6 still work after Phase 7 changes
4. **Live Radius Validation Checklist** — repeatable execution steps for any operator

**Outcome:** A testable, observable matrix that will be executed by the team before Phase 7 approval and can be reused for future release confidence.

---

## Prerequisites for Phase 7 Validation Execution

Before **any** of the scenarios below can be run, the following must be in place:

### Code & Artifact Prerequisites

- [x] `dotnet build RadiusClaim.slnx` completes with zero errors and zero warnings
- [x] `az bicep build --file infra/radius/app.bicep` parses without errors
- [x] Container images (`expense-api`, `workflow-engine`, `notification-svc`) are built and available in the container registry
- [x] Radius recipes are published to GHCR under `ghcr.io/radiusclaim/recipes` (or operator's chosen registry)

### Infrastructure Prerequisites

- [ ] Kubernetes cluster is provisioned and reachable (`kubectl cluster-info`)
- [ ] Dapr is installed on the cluster with `--wait` semantics (verified via `dapr status -k`)
- [ ] Radius environment is registered with `rad env list` and points to a valid Azure subscription
- [ ] Azure subscription has quota for:
  - Azure Storage Account (Blob) for state store
  - Azure Service Bus for pub/sub
  - Optional: Azure Key Vault for secrets store
- [ ] Service Principal or Workload Identity is configured with `Storage Blob Data Contributor` and `Azure Service Bus Data Owner` roles on the backing resources
- [ ] Bootstrap script has run successfully: `./scripts/bootstrap.sh --yes` (or manual walkthrough completed)

### Platform Health Checks

Before running scenarios, verify:

```bash
# Kubernetes cluster reachable
kubectl cluster-info

# Dapr healthy and responsive
dapr status -k

# Radius installation healthy
rad env list
rad app list

# Namespace exists and pods are running
kubectl get ns radiusclaim-azure
kubectl get pods -n radiusclaim-azure

# Dapr sidecars injected and healthy (no CrashLoopBackOff)
kubectl get pods -n radiusclaim-azure -o jsonpath='{.items[*].spec.containers[*].name}' | grep -q daprd && echo "✓ Dapr sidecars present" || echo "✗ Missing daprd sidecars"

# expense-api is callable (via public gateway or port-forward)
export EXPENSE_API_BASE_URL="https://$(rad app show -a radiusclaim -o json | jq -r '.properties.status.publicEndpoints[0].url // empty')" || \
  (kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &) && \
  export EXPENSE_API_BASE_URL="http://127.0.0.1:8080"
  
curl "${EXPENSE_API_BASE_URL}/health"
```

---

## Scenario 1: Happy Path — Auto-Approve Flow ($50 Expense)

**Goal:** Prove the baseline submit → approve → reimburse journey for small expenses.

**Precondition:** expense-api is deployed and healthy.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 1.1 | Submit $50 expense via `POST /expenses` | Returns 201 with `expenseId` and `correlationId` in response; status: `Submitted` | cURL response JSON; `expenseId` is UUID-like; `submittedAtUtc` is recent |
| 1.2 | Poll `GET /expenses/{expenseId}` immediately (< 2 sec) | Status remains `Submitted` (workflow not yet started) | Same `expenseId`, same `correlationId` |
| 1.3 | Wait 3–5 seconds, poll again | Status changes to `Approved` (workflow auto-approved) | Status field shows `Approved` |
| 1.4 | Wait 2–3 seconds, poll again | Status changes to `Reimbursed` (reimbursement activity completed) | Status field shows `Reimbursed` |
| 1.5 | Check `notification-svc` logs | Logs show `ExpenseApproved` event with matching `CorrelationId` | `kubectl logs -n radiusclaim-azure -l app.kubernetes.io/name=notification-svc` contains: `EventType: ExpenseApproved`, `CorrelationId: <matching-uuid>`, `Amount: 50.00` |
| 1.6 | Verify state persistence | State store records the final state | No errors in workflow-engine logs; expense-api returns correct status on later poll |

**Acceptance Criteria:**
- All steps execute without error
- Status transitions happen in the correct order and timing
- CorrelationId is preserved through all events
- Amount ($50.00) is preserved in notification logs

**Failure Modes:**
- Submission fails (500 error) → Check expense-api pod logs for Dapr initialization errors
- Status stuck on `Submitted` → Check workflow-engine pod logs; verify Dapr service invocation works
- Notification never appears → Check pub/sub component is healthy; verify notification-svc is running
- Amount is mutated or lost → Critical data integrity failure; reject release

---

## Scenario 2: Happy Path — Manual Review Flow ($150 Expense)

**Goal:** Prove the submit → hold-for-review journey for large expenses.

**Precondition:** expense-api is deployed and healthy.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 2.1 | Submit $150 expense via `POST /expenses` | Returns 201 with `expenseId` and `correlationId`; status: `Submitted` | cURL response JSON; `expenseId` is unique |
| 2.2 | Poll immediately (< 2 sec) | Status remains `Submitted` | Same `expenseId` and `correlationId` |
| 2.3 | Wait 3–5 seconds, poll again | Status changes to `ManualReviewRequested` (threshold exceeded, held) | Status field shows `ManualReviewRequested` (NOT `Approved`, NOT `Rejected`) |
| 2.4 | Wait 2–3 seconds, poll again | Status remains `ManualReviewRequested` (no automatic further progression) | Same status, no involuntary auto-rejection |
| 2.5 | Check `notification-svc` logs | Logs show `ManualReviewRequested` event with matching `CorrelationId` | `EventType: ManualReviewRequested`, `CorrelationId: <matching-uuid>`, `Amount: 150.00` |
| 2.6 | Verify state persistence | State store maintains the hold status | No errors in workflow-engine logs |

**Acceptance Criteria:**
- Status correctly transitions to `ManualReviewRequested` (not `Approved` or `Rejected`)
- Status **remains** in manual-review state (no automatic rejection or approval)
- CorrelationId is preserved
- Amount ($150.00) is preserved in notification logs
- Distinction between "denied" and "held for review" is observable

**Failure Modes:**
- Auto-approves $150 → Threshold logic is broken; critical rejection
- Auto-rejects $150 → Workflow is incorrectly denying; critical rejection
- Status gets stuck on `Submitted` → Workflow invocation failure
- Notification has wrong event type → Pub/sub event mismapping; critical rejection

---

## Scenario 3: Happy Path — Boundary Case ($100.00 Expense)

**Goal:** Prove the threshold boundary is correctly implemented (>= $100 → manual review, < $100 → auto-approve).

**Precondition:** expense-api is deployed and healthy.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 3.1 | Submit exactly $100.00 | Returns 201 with `expenseId` and `correlationId` | Response is successful |
| 3.2 | Poll after 3–5 seconds | Status changes to `ManualReviewRequested` (not `Approved`) | Status field shows `ManualReviewRequested` |
| 3.3 | Check notification logs | Event is `ManualReviewRequested` (not `ExpenseApproved`) | `EventType: ManualReviewRequested`, `Amount: 100.00` |
| 3.4 | Submit $99.99 | Returns 201 with `expenseId` and `correlationId` | Response is successful |
| 3.5 | Poll after 3–5 seconds | Status changes to `Approved` (below threshold, auto-approved) | Status field shows `Approved` |
| 3.6 | Check notification logs | Event is `ExpenseApproved` | `EventType: ExpenseApproved`, `Amount: 99.99` |
| 3.7 | Poll again after 2–3 seconds | Status changes to `Reimbursed` | Status field shows `Reimbursed` |

**Acceptance Criteria:**
- $100.00 enters manual review (not auto-approved)
- $99.99 auto-approves
- Threshold boundary is sharp (no ambiguity at $100.00)

**Failure Modes:**
- $100.00 auto-approves → Threshold logic is off-by-one; critical rejection
- $99.99 goes to manual review → Threshold logic is inverted; critical rejection

---

## Scenario 4: Happy Path — State Persistence After Container Restart

**Goal:** Prove that expense state survives a pod restart (Dapr state store is the source of truth).

**Precondition:** expense-api is deployed; a $50 expense has been submitted and approved.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 4.1 | Submit a $50 expense; wait for `Approved` status | Expense is in state store with status `Approved` | Poll confirms `Approved` |
| 4.2 | Delete the expense-api pod | Pod restarts (controlled restart, not crash) | `kubectl delete pod -n radiusclaim-azure <expense-api-pod>` succeeds; new pod is scheduled |
| 4.3 | Wait for new pod to be `Running` and ready | Pod starts and daprd sidecar connects | `kubectl get pods -n radiusclaim-azure` shows new pod in `Running` state with ready `2/2` |
| 4.4 | Poll the expense status immediately | Status is still `Approved` (recovered from state store, not lost) | `GET /expenses/{expenseId}` returns `Approved` |
| 4.5 | Verify amount is correct | Amount field matches original submission ($50.00) | Response JSON shows `amount: 50.00` |

**Acceptance Criteria:**
- Expense state is recovered correctly after pod restart
- Amount is not mutated or lost
- Status transitions resume if the expense was in-flight

**Failure Modes:**
- Status is lost or reset to `Submitted` → State store is not the source of truth; critical failure
- Amount is mutated → Data integrity failure; critical rejection
- Pod fails to restart → Deployment/Dapr configuration issue (not blocking Phase 7, but operator must resolve)

---

## Scenario 5: Edge Case — Concurrent Submissions from Same User

**Goal:** Prove that the system handles concurrent expense submissions without losing state or creating duplicates.

**Precondition:** expense-api is deployed and healthy.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 5.1 | Submit expense #1 ($50) and expense #2 ($150) **simultaneously** (within 100ms) | Both return 201 with distinct `expenseId` values; both have `Submitted` status | Two cURL requests in quick succession return two different IDs |
| 5.2 | Poll expense #1 after 3–5 seconds | Status is `Approved` (auto-approve for $50) | Status field shows `Approved` |
| 5.3 | Poll expense #2 after 3–5 seconds | Status is `ManualReviewRequested` (manual review for $150) | Status field shows `ManualReviewRequested` |
| 5.4 | Poll both again after 2–3 seconds | Expense #1 is `Reimbursed`; Expense #2 remains `ManualReviewRequested` | Each progresses independently |
| 5.5 | Verify state store has both records | State store contains both `expenseId` entries with correct amounts and statuses | No merge or collision; both amounts preserved ($50.00 and $150.00) |
| 5.6 | Check notification logs for both events | Two notifications appear (one `ExpenseApproved`, one `ManualReviewRequested`) with correct `CorrelationId` values | Two distinct `CorrelationId` values; one per event; amounts match |

**Acceptance Criteria:**
- No race conditions or lost submissions
- Each expense has a unique `expenseId` and `correlationId`
- Both expenses progress independently based on their amount
- State store contains both records without collision
- Two distinct notifications appear

**Failure Modes:**
- One submission is lost → Race condition; critical failure
- Both get the same `expenseId` → UUID generation collision; critical rejection
- State is merged or overwritten → Data corruption; critical failure
- Only one notification appears → Pub/sub event loss; critical failure

---

## Scenario 6: Edge Case — Approval Race: Approval Arrives Before Workflow Processes Submit

**Goal:** Prove the system handles the case where approval decision is received before the workflow engine has fully processed the submission.

**Precondition:** expense-api is deployed; workflow orchestration uses Dapr Workflows (durable saga pattern).

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 6.1 | Submit a $50 expense | Returns 201 with `Submitted` status | cURL response shows `Submitted` |
| 6.2 | Before the workflow engine processes the submission, manually inspect the state store | The expense record exists with status `Submitted` | State store key is present; status is `Submitted` |
| 6.3 | Wait for workflow to process and auto-approve | Workflow decides → Approval activity → Reimbursement activity | Poll shows progression: `Submitted` → `Approved` → `Reimbursed` |
| 6.4 | Verify final state is consistent | Final state is `Reimbursed` (not corrupted by race) | Last poll shows `Reimbursed` with correct amount |

**Acceptance Criteria:**
- Workflow state machine correctly handles the transition from `Submitted` → `Approved` even if state store already has the record
- Final state is deterministic and not corrupted by timing issues

**Failure Modes:**
- State is corrupted or stuck in an intermediate state → Workflow race condition; critical failure
- Approval decision is lost → Activity logic failure; critical rejection

---

## Scenario 7: Edge Case — Denied Expense (Explicit Denial Flow)

**Goal:** Test the expense denial/rejection flow if the workflow supports it (scoped per decisions).

**Precondition:** Workflow supports an explicit denial/rejection branch (if in scope; mark as N/A if deferred).

**Test Steps (if denial is in scope):**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 7.1 | Submit a $200 expense | Returns 201 with `Submitted` status | cURL response |
| 7.2 | Via admin API or test harness, trigger a denial decision | Denial is recorded | (Test harness dependent; may require separate admin endpoint) |
| 7.3 | Poll expense status | Status changes to `Denied` or `Rejected` | Status field reflects denial |
| 7.4 | Check notification logs | Notification event shows denial reason | Event logs show reason (fraud, duplicate, compliance issue, etc.) |
| 7.5 | Verify reimbursement is NOT triggered | Reimbursement status remains null or "not applicable" | State does not progress to `Reimbursed` |

**Acceptance Criteria:**
- Denial path is observable and distinct from auto-approve and manual-review paths
- Reimbursement is blocked for denied expenses
- Denial reason is traceable in logs

**Blocking Note:** This scenario is currently **out of scope for Phase 7**. The workflow supports auto-approve and manual-review, but explicit denial is deferred to Phase 8+. Mark as `[NOT_TESTED_PHASE_7]` in approval.

---

## Scenario 8: Failure Path — Dapr State Store Unavailable

**Goal:** Prove the system fails gracefully when the Dapr state store is unreachable.

**Precondition:** expense-api is deployed; state store component is healthy initially.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 8.1 | Break the state store (simulate unavailability): Patch the Dapr component or revoke RBAC from the backing Azure Storage Account | Component becomes unhealthy | `kubectl describe dapr statestore -n radiusclaim-azure` shows error; `dapr status -k` may show degraded status |
| 8.2 | Submit a new $50 expense | Request fails with a meaningful error (5xx, not 2xx) | cURL returns 500 or 503; logs show state store access error |
| 8.3 | Verify the error is informative | Error message or logs indicate state store failure, not generic "internal error" | expense-api logs show "state store unavailable" or similar |
| 8.4 | Restore the state store (fix RBAC, re-enable component) | Component becomes healthy | `dapr status -k` shows healthy |
| 8.5 | Re-submit the same expense | Request succeeds; expense is persisted | cURL returns 201; expense is stored |

**Acceptance Criteria:**
- Submission fails gracefully (5xx, not 2xx)
- Error message is informative enough for troubleshooting
- System recovers after state store is restored
- No data corruption or inconsistency after recovery

**Failure Modes:**
- Submission silently succeeds but expense is lost → Data loss; critical failure
- Error message is cryptic ("internal error") → Operator cannot troubleshoot
- System does not recover after state store is restored → Stuck state; critical failure

---

## Scenario 9: Failure Path — Pub/Sub Component Unavailable (Notification Delivery Failure)

**Goal:** Prove the system handles pub/sub failures: workflow completes, but notification may not deliver.

**Precondition:** expense-api is deployed; pub/sub component is healthy initially.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 9.1 | Break the pub/sub component (revoke RBAC from Azure Service Bus, or scale down notification-svc) | Component becomes unhealthy | `kubectl describe dapr pubsub -n radiusclaim-azure` shows error |
| 9.2 | Submit a $50 expense | Submission succeeds (state store is still working) | cURL returns 201 with `Submitted` status |
| 9.3 | Wait for workflow to process | Workflow auto-approves; status progresses to `Approved` → `Reimbursed` | Poll shows `Reimbursed` |
| 9.4 | Check notification logs | No notification appears (or notification appears with error) | `kubectl logs -n radiusclaim-azure -l app.kubernetes.io/name=notification-svc` shows error or is empty |
| 9.5 | Restore pub/sub component | Component becomes healthy | `dapr status -k` shows healthy |
| 9.6 | Verify notification delivery for future expenses | New expense submissions trigger notifications normally | Poll shows workflow progression; logs show notifications |

**Acceptance Criteria:**
- Workflow completes despite pub/sub failure (workflow is resilient)
- Notification delivery is attempted but fails gracefully (not a blocker to expense approval)
- System recovers after pub/sub is restored
- Operator understands that notification delivery is best-effort, not guaranteed in this phase

**Failure Modes:**
- Workflow gets stuck waiting for notification → Design flaw; critical failure
- Submission fails because notification fails → Incorrect dependency; critical failure
- Exception is unhandled and pod crashes → Error handling deficiency

---

## Scenario 10: Failure Path — Workflow Engine Pod Crash (Durability)

**Goal:** Prove that in-flight workflows are durable and resume after a crash.

**Precondition:** expense-api is deployed; workflow-engine is running.

**Test Steps:**

| Step | Action | Expected Result | Observable Evidence |
|------|--------|-----------------|---------------------|
| 10.1 | Submit a $50 expense | Returns 201 with `Submitted` status | cURL response |
| 10.2 | Within 1–2 seconds (before workflow completes), kill the workflow-engine pod | Pod crashes and Kubernetes restarts it | `kubectl delete pod -n radiusclaim-azure <workflow-engine-pod>` succeeds; new pod is scheduled |
| 10.3 | Wait 5–10 seconds for pod to restart and daprd to reconnect | Pod starts; daprd sidecar connects to Dapr control plane | `kubectl get pods -n radiusclaim-azure` shows new workflow-engine pod in `Running` state |
| 10.4 | Poll the expense status | Workflow resumes from the checkpoint where it was interrupted and completes | Poll shows progression: `Submitted` → `Approved` → `Reimbursed` |
| 10.5 | Verify notification is delivered | Notification event is published once (idempotent, not duplicated) | Log shows one `ExpenseApproved` event with matching `CorrelationId` |

**Acceptance Criteria:**
- Workflow resumes correctly after pod crash
- No data loss or corruption
- Notification is delivered exactly once (not duplicated)
- Expense reaches final state without operator intervention

**Failure Modes:**
- Workflow is lost and never completes → Dapr Workflows not truly durable; critical failure
- Workflow duplicates the approval or reimbursement → Idempotency failure; critical rejection
- Notification is sent twice → Pub/sub delivery guarantee issue

---

## Regression Gates: Phases 1–6 Stability

These scenarios verify that Phase 7 changes do not break existing functionality.

### Gate 1: Dapr SDK Integration Still Works

**Test:** Verify that Dapr SDKs (state store, service invocation, workflows, pub/sub) still initialize correctly after any Phase 7 changes.

| Test | Expected Result | Observable Evidence |
|------|-----------------|---------------------|
| expense-api pod starts without errors | daprd sidecar initializes; no `CrashLoopBackOff` | `kubectl logs -n radiusclaim-azure <expense-api-pod> -c daprd` shows "initialized" message; pod is `Running` with ready `2/2` |
| workflow-engine pod starts without errors | daprd sidecar initializes; orchestration runtime ready | `kubectl logs -n radiusclaim-azure <workflow-engine-pod> -c daprd` shows initialization success |
| notification-svc pod starts without errors | daprd sidecar initializes; subscription active | `kubectl logs -n radiusclaim-azure <notification-svc-pod> -c daprd` shows ready state |
| Health endpoint responds | `GET /health` returns `{ "status": "ok" }` | cURL to `http://<expense-api>/health` returns 200 with JSON |

### Gate 2: Service Invocation (Expense-API → Workflow-Engine)

**Test:** Verify that expense-api can still invoke the workflow-engine via Dapr service invocation.

| Test | Expected Result | Observable Evidence |
|------|-----------------|---------------------|
| Submit an expense triggers workflow invocation | Workflow engine receives the request | workflow-engine logs show: `Received expense submission for expenseId: <uuid>` |
| Workflow runs to completion | Workflow activities execute in sequence | Logs show: `ApproveExpenseActivity`, `ReimbursementActivity` running |
| Status updates are written to state store | Final status is available via GET | Poll shows final status (e.g., `Reimbursed`) |

### Gate 3: Pub/Sub Contract (Workflow → Notification-Svc)

**Test:** Verify that workflow events are published and notification-svc consumes them.

| Test | Expected Result | Observable Evidence |
|------|-----------------|---------------------|
| Workflow publishes approval event | notification-svc receives the event | notification-svc logs show: `Received event type: ExpenseApproved` |
| notification-svc consumes and logs the event | Notification is recorded | Logs show full event details: `CorrelationId`, `Amount`, `Recipient` |
| Event is published with correct topic/subject | Dapr pub/sub routing works | No "unhandled event" or routing errors in logs |

### Gate 4: State Store Persistence (Dapr ↔ Azure Blob)

**Test:** Verify that expense records persist in the state store without loss or mutation.

| Test | Expected Result | Observable Evidence |
|------|-----------------|---------------------|
| Submit expense; verify state store record exists | Record is written to Azure Storage Account (Blob) | `kubectl describe dapr statestore -n radiusclaim-azure` shows healthy; workflow-engine logs show state write success |
| Retrieve expense after submission | Record is read correctly | Poll returns correct `expenseId`, `amount`, `status` |
| Update expense status | New status is persisted | Poll shows updated status; no stale reads |
| Restart expense-api pod; retrieve expense | Record is still accessible | New pod retrieves record from state store without data loss |

### Gate 5: Dapr Component Projections (Radius Recipe Output)

**Test:** Verify that Dapr component projections are still valid and accessible.

| Test | Expected Result | Observable Evidence |
|------|-----------------|---------------------|
| Dapr component `statestore` projects successfully | Dapr sidecar connects to state store | `dapr status -k` shows `statestore` as `healthy` |
| Dapr component `pubsub` projects successfully | Dapr sidecar connects to pub/sub broker | `dapr status -k` shows `pubsub` as `healthy` |
| Dapr component `platform-secrets` projects (if used) | Dapr sidecar connects to secrets store | `dapr status -k` shows `platform-secrets` as `healthy` (or "N/A" if not used in demo flow) |
| All components use correct auth (Entra workload identity) | RBAC role assignments are in place | `az role assignment list --assignee <dapr-principal-id> --scope <storage-account-id>` shows `Storage Blob Data Contributor` |

---

## Live Radius Validation Checklist

This checklist **walks an operator through the entire Phase 7 validation** and is the authoritative execution guide.

### Pre-Flight Checks

**Goal:** Ensure the environment is ready before running scenarios.

**Checklist:**

- [ ] **Azure Context**
  ```bash
  az account show
  ```
  Expected: Correct subscription ID and tenant ID displayed.
  
- [ ] **Kubernetes Cluster Reachable**
  ```bash
  kubectl cluster-info
  kubectl get nodes
  ```
  Expected: At least one node is `Ready`.

- [ ] **Dapr Installed and Healthy**
  ```bash
  dapr --version
  dapr status -k
  ```
  Expected: Dapr CLI present; control plane pods are `Running` and services are `healthy`.

- [ ] **Radius Installed and Healthy**
  ```bash
  rad version
  rad env list
  ```
  Expected: Radius CLI present; at least one environment listed.

- [ ] **Active Radius Workspace**
  ```bash
  rad workspace show
  ```
  Expected: Workspace is set; environment is valid (e.g., `radiusclaim-dev` or similar).

- [ ] **Kubernetes Namespace Exists**
  ```bash
  kubectl get ns radiusclaim-azure
  ```
  Expected: Namespace is `Active`.

- [ ] **Container Registry Accessible**
  ```bash
  az acr login --name <registry-name> (if using ACR)
  # or
  echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USERNAME --password-stdin (if using GHCR)
  ```
  Expected: Login succeeds.

- [ ] **Azure Storage Account for State Store Exists**
  ```bash
  az storage account list --query "[?contains(name, 'statestore')]" --output table
  ```
  Expected: Storage account is listed with `ProvisioningState: Succeeded`.

- [ ] **Azure Service Bus for Pub/Sub Exists**
  ```bash
  az servicebus namespace list --query "[?contains(name, 'pubsub')]" --output table
  ```
  Expected: Service Bus namespace is listed and active.

---

### Deployment Validation

**Goal:** Verify that the Radius deployment is complete and all pods are healthy.

**Checklist:**

- [ ] **Radius Application Deployed**
  ```bash
  rad app list
  rad app show -a radiusclaim
  ```
  Expected: Application `radiusclaim` is listed; status is `healthy` or `provisioned`.

- [ ] **All Workload Pods Are Running**
  ```bash
  kubectl get pods -n radiusclaim-azure
  ```
  Expected: Three pods are `Running` with ready `2/2`:
  - `expense-api-*`
  - `workflow-engine-*`
  - `notification-svc-*`
  
  If any pod is `CrashLoopBackOff`, check logs:
  ```bash
  kubectl logs -n radiusclaim-azure <pod-name> -c <container-name>
  ```

- [ ] **Dapr Sidecars Are Healthy**
  ```bash
  kubectl get pods -n radiusclaim-azure -o json | jq '.items[] | {name: .metadata.name, daprd: (.spec.containers[] | select(.name=="daprd") | .name)}'
  ```
  Expected: Each pod has a `daprd` sidecar; no errors in startup logs.

- [ ] **Dapr Component Projections Are Healthy**
  ```bash
  kubectl describe dapr statestore -n radiusclaim-azure
  kubectl describe dapr pubsub -n radiusclaim-azure
  kubectl describe dapr platform-secrets -n radiusclaim-azure (if applicable)
  ```
  Expected: Each component shows `Ready: True`; no errors.

- [ ] **Public Gateway for expense-api**
  ```bash
  rad app show -a radiusclaim -o json | jq '.properties.status.publicEndpoints'
  ```
  Expected: At least one endpoint with `url` pointing to a public HTTPS address (or note if using port-forward fallback).

- [ ] **Retrieve Expense-API Base URL**
  ```bash
  export EXPENSE_API_BASE_URL="https://$(rad app show -a radiusclaim -o json | jq -r '.properties.status.publicEndpoints[0].url // empty')"
  # If empty, use port-forward fallback:
  # kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &
  # export EXPENSE_API_BASE_URL="http://127.0.0.1:8080"
  ```
  Expected: Base URL is set and non-empty.

---

### Runtime Validation

**Goal:** Execute the happy path scenarios and observe behavior.

**Checklist:**

- [ ] **Health Endpoint Responds**
  ```bash
  curl -v "${EXPENSE_API_BASE_URL}/health"
  ```
  Expected: HTTP 200 with JSON response `{ "status": "ok" }`.

- [ ] **Submit $50 Expense (Auto-Approve Flow)**
  ```bash
  RESPONSE=$(curl -s -X POST "${EXPENSE_API_BASE_URL}/expenses" \
    -H 'Content-Type: application/json' \
    -d '{
      "employeeId": "emp-demo-001",
      "amount": 50.00,
      "currency": "USD",
      "description": "Office supplies"
    }')
  
  EXPENSE_ID=$(echo "$RESPONSE" | jq -r '.expenseId')
  CORRELATION_ID=$(echo "$RESPONSE" | jq -r '.correlationId')
  
  echo "ExpenseId: $EXPENSE_ID"
  echo "CorrelationId: $CORRELATION_ID"
  ```
  Expected: HTTP 201; response contains `expenseId` and `correlationId`; status is `Submitted`.

- [ ] **Poll for Auto-Approval (Wait 5–8 seconds)**
  ```bash
  sleep 5
  curl -s "${EXPENSE_API_BASE_URL}/expenses/${EXPENSE_ID}" | jq '.status'
  ```
  Expected: Status is `Approved`.

- [ ] **Poll for Reimbursement (Wait 2–3 seconds)**
  ```bash
  sleep 3
  curl -s "${EXPENSE_API_BASE_URL}/expenses/${EXPENSE_ID}" | jq '.status'
  ```
  Expected: Status is `Reimbursed`.

- [ ] **Verify Notification (Wait 5–10 seconds for log propagation)**
  ```bash
  sleep 5
  kubectl logs -n radiusclaim-azure -l app.kubernetes.io/name=notification-svc --tail=50 | grep -A 5 "${CORRELATION_ID}"
  ```
  Expected: Logs contain `EventType: ExpenseApproved`, `CorrelationId: ${CORRELATION_ID}`, `Amount: 50.00`.

- [ ] **Submit $150 Expense (Manual-Review Flow)**
  ```bash
  RESPONSE=$(curl -s -X POST "${EXPENSE_API_BASE_URL}/expenses" \
    -H 'Content-Type: application/json' \
    -d '{
      "employeeId": "emp-demo-002",
      "amount": 150.00,
      "currency": "USD",
      "description": "Conference travel"
    }')
  
  EXPENSE_ID_2=$(echo "$RESPONSE" | jq -r '.expenseId')
  CORRELATION_ID_2=$(echo "$RESPONSE" | jq -r '.correlationId')
  
  echo "ExpenseId: $EXPENSE_ID_2"
  echo "CorrelationId: $CORRELATION_ID_2"
  ```
  Expected: HTTP 201; status is `Submitted`.

- [ ] **Poll for Manual-Review Hold (Wait 5–8 seconds)**
  ```bash
  sleep 5
  curl -s "${EXPENSE_API_BASE_URL}/expenses/${EXPENSE_ID_2}" | jq '.status'
  ```
  Expected: Status is `ManualReviewRequested` (NOT `Approved`, NOT `Rejected`).

- [ ] **Verify Manual-Review Notification**
  ```bash
  kubectl logs -n radiusclaim-azure -l app.kubernetes.io/name=notification-svc --tail=50 | grep -A 5 "${CORRELATION_ID_2}"
  ```
  Expected: Logs contain `EventType: ManualReviewRequested`, `CorrelationId: ${CORRELATION_ID_2}`, `Amount: 150.00`.

- [ ] **Boundary Case: Submit $100.00 (Exactly)**
  ```bash
  RESPONSE=$(curl -s -X POST "${EXPENSE_API_BASE_URL}/expenses" \
    -H 'Content-Type: application/json' \
    -d '{
      "employeeId": "emp-demo-003",
      "amount": 100.00,
      "currency": "USD",
      "description": "Boundary test"
    }')
  
  EXPENSE_ID_3=$(echo "$RESPONSE" | jq -r '.expenseId')
  sleep 5
  curl -s "${EXPENSE_API_BASE_URL}/expenses/${EXPENSE_ID_3}" | jq '.status'
  ```
  Expected: Status is `ManualReviewRequested` (NOT `Approved`).

---

### Cleanup Validation

**Goal:** Ensure the environment can be torn down cleanly.

**Checklist:**

- [ ] **Delete Radius Application**
  ```bash
  rad app delete radiusclaim
  ```
  Expected: Deletion succeeds; workload pods are terminated.

- [ ] **Verify Kubernetes Namespace Is Cleaned Up**
  ```bash
  kubectl get pods -n radiusclaim-azure
  ```
  Expected: No pods are running (or namespace deletion in progress).

- [ ] **Verify Dapr Components Are Removed**
  ```bash
  kubectl get dapr -n radiusclaim-azure
  ```
  Expected: No components listed (or empty output).

- [ ] **Verify Azure Resources Can Be Reclaimed (Optional)**
  ```bash
  az storage account list --query "[?contains(name, 'statestore')]" --output table
  az servicebus namespace list --query "[?contains(name, 'pubsub')]" --output table
  ```
  Expected: Resources are deleted or marked for deletion (operator decides retention policy).

---

## Validation Execution Path: Happy Path Only (Recommended for Phase 7)

For Phase 7 release approval, the **minimum execution** is:

1. **Pre-Flight Checks** (all items)
2. **Deployment Validation** (all items)
3. **Runtime Validation** (happy path scenarios: $50, $150, $100.00)
4. **Cleanup Validation** (at least the Radius app delete step)

**Time estimate:** 20–30 minutes with a live cluster.

**Evidence to collect:**
- Screenshot of pre-flight checks (all pass)
- cURL responses showing all three expense submissions and status progressions
- `kubectl logs` output showing both `ExpenseApproved` and `ManualReviewRequested` notifications with matching `CorrelationId` values
- Final cleanup confirmation (pods deleted, namespace clean)

**Approval sign-off format:**
```
Phase 7 Live Validation — APPROVED

Date: [timestamp]
Validator: [name]
Environment: [cluster-name], [region], [subscription-id]

Evidence:
- Pre-flight: [pass/fail]
- Deployment: [pass/fail]
- $50 flow: [pass/fail] — Status progression: Submitted → Approved → Reimbursed
- $150 flow: [pass/fail] — Status: ManualReviewRequested
- $100.00 boundary: [pass/fail] — Status: ManualReviewRequested
- Notifications: [pass/fail] — Both events logged with correct CorrelationId
- Cleanup: [pass/fail]

Overall: APPROVED / BLOCKED

Signature: [name]
```

---

## Edge Cases & Failure Paths: Optional (Phase 7+)

The following scenarios are **designed for future validation** and are not required for Phase 7 approval:

- Scenario 5 (Concurrent Submissions)
- Scenario 6 (Approval Race)
- Scenario 7 (Denial Flow) — Currently out of scope
- Scenario 8 (State Store Unavailable)
- Scenario 9 (Pub/Sub Unavailable)
- Scenario 10 (Workflow Engine Crash)

These scenarios may be executed as part of **integration testing** or **chaos engineering** in Phase 8+.

---

## Regression Gates: Automation Opportunity

Each regression gate can be automated:

1. **Gate 1:** Health endpoint polling script
2. **Gate 2:** Service invocation test with known expense submission
3. **Gate 3:** Pub/sub event verification with log grep
4. **Gate 4:** State store round-trip test (write, wait, read, verify)
5. **Gate 5:** Dapr component health check via `dapr status -k`

See `scripts/validate-deployment.sh` for the current automated checks; expansion into full scenario automation is recommended for Phase 8.

---

## Marks for Entra Auth Dependencies

The following sections depend on **Entra auth setup** (workload identity or service principal) and cannot proceed until Graham's auth pivot is complete:

- [ENTRA_AUTH_SETUP_REQUIRED] Pre-Flight Checks: Azure Context, Service Principal / Workload Identity verification
- [ENTRA_AUTH_SETUP_REQUIRED] Deployment Validation: Dapr Component Projections (RBAC role assignments)
- [ENTRA_AUTH_SETUP_REQUIRED] State Store Persistence: Azure Storage Account access via Entra
- [ENTRA_AUTH_SETUP_REQUIRED] All failure paths involving state store or pub/sub unavailability

**Blocker Status:** Entra auth pivot completed ✅ (2026-03-26). All scenarios can proceed.

---

## Summary

**Phase 7 Validation Coverage:**

| Category | Scenarios | Scope |
|----------|-----------|-------|
| Happy Paths | 4 (auto-approve, manual-review, boundary, persistence) | **Required for Phase 7** |
| Edge Cases | 3 (concurrent, race condition, denial) | Optional; Phase 8+ |
| Failure Paths | 3 (state store, pub/sub, workflow crash) | Optional; Phase 8+ |
| Regression Gates | 5 (SDK, service invocation, pub/sub, state store, components) | **Required for Phase 7** |
| Live Validation Checklist | Pre-flight, deployment, runtime, cleanup | **Required for Phase 7** |

**Release Confidence:** Phase 7 can be approved once the **happy paths** and **regression gates** pass against a live Radius environment with Dapr + Azure backing services.

---

## Revision History

| Date       | Change                                       | Author |
|------------|----------------------------------------------|--------|
| 2026-03-27 | Phase 7 validation scenarios and checklist   | Karen  |


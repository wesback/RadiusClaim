# Phase 7 Demo Walkthrough

> **Audience:** Platform engineers and demo pilots  
> **Duration:** ~10 minutes  
> **Goal:** Show the auto-approve and manual-review flows end-to-end with observable evidence

---

## Prerequisites

- RadiusClaim is deployed to a Kubernetes cluster (AKS as the primary example, or any K8s with Dapr and Radius)
- `expense-api` is reachable at a public Radius gateway URL printed by `rad deploy` (preferred) or via `kubectl port-forward` fallback
- `notification-svc` is running and logging to Kubernetes logs (visible via `kubectl logs`)

Set a base URL before the demo:

```bash
# Preferred: the public endpoint printed by rad deploy
export EXPENSE_API_BASE_URL="https://<expense-api-base-url>"

# Fallback if the public address is not yet reachable from your machine:
# kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &
# export EXPENSE_API_BASE_URL="http://127.0.0.1:8080"
```

### Optional visual path

If you want to run the same demo in a browser, open `${EXPENSE_API_BASE_URL}/app`.

- The hosted UI submits the same `POST /expenses` requests as the curl examples below
- It also shows recent expense history, correlation IDs, and workflow telemetry in one place
- This is useful for live demos where you want the RadiusClaim story to feel more product-like without changing the backend flow

---

## The Two Flows

This demo proves two distinct expense workflows:

1. **Auto-Approve Flow** (`$50` example) — Expenses under $100 auto-approve instantly and proceed to reimbursement
2. **Manual-Review Flow** (`$150` example) — Expenses $100+ are held for manual review, not auto-rejected

---

## Flow 1: Auto-Approve ($50 expense)

### Step 1: Submit a small expense

```bash
curl -X POST "${EXPENSE_API_BASE_URL}/expenses" \
  -H 'Content-Type: application/json' \
  -d '{
    "employeeId": "emp-demo-001",
    "amount": 50.00,
    "currency": "USD",
    "description": "Office supplies"
  }'
```

**Expected response:**
```json
{
  "expenseId": "exp-<uuid>",
  "correlationId": "<uuid>",
  "employeeId": "emp-demo-001",
  "amount": 50.00,
  "currency": "USD",
  "description": "Office supplies",
  "submittedAtUtc": "2026-03-24T14:30:00Z",
  "status": "Submitted"
}
```

**What to note:**
- `expenseId` is the stable business identifier
- `correlationId` is created at submission and will reappear in approval and notification events
- Status is immediately `Submitted` (API accepted the request)

### Step 2: Poll for status

```bash
curl "${EXPENSE_API_BASE_URL}/expenses/exp-<uuid>"
```

**Expected progression (each poll):**
1. `Submitted` (initial)
2. `Approved` (workflow auto-approved because amount < $100)
3. `Reimbursed` (workflow processed reimbursement)

Each status change happens asynchronously as the workflow progresses through activities.

### Step 3: Observe the notification

Check the `notification-svc` logs in Kubernetes:

```bash
kubectl logs -n radiusclaim-azure -l app=notification-svc --tail=100
```

**Expected log output (contains):**
```
ExpenseId: exp-<uuid>
CorrelationId: <uuid>
EventType: ExpenseApproved
DecisionSource: Auto
Recipient: emp-demo-001@company.com
Subject: Your expense for $50.00 has been approved
Message: ...
OccurredAtUtc: 2026-03-24T14:30:15Z
```

**What this proves:**
- The `$50` expense auto-approved
- The workflow published an `ExpenseApproved` event
- The notification service consumed the event and logged it
- The correlation chain is traceable: submission → approval → notification all share `CorrelationId`

---

## Flow 2: Manual Review ($150 expense)

### Step 1: Submit a large expense

```bash
curl -X POST "${EXPENSE_API_BASE_URL}/expenses" \
  -H 'Content-Type: application/json' \
  -d '{
    "employeeId": "emp-demo-002",
    "amount": 150.00,
    "currency": "USD",
    "description": "Conference travel"
  }'
```

**Expected response:**
```json
{
  "expenseId": "exp-<uuid2>",
  "correlationId": "<uuid2>",
  "employeeId": "emp-demo-002",
  "amount": 150.00,
  "currency": "USD",
  "description": "Conference travel",
  "submittedAtUtc": "2026-03-24T14:35:00Z",
  "status": "Submitted"
}
```

### Step 2: Poll for status

```bash
curl "${EXPENSE_API_BASE_URL}/expenses/exp-<uuid2>"
```

**Expected progression:**
1. `Submitted` (initial)
2. `ManualReviewRequested` (workflow flagged it for human review because amount >= $100)
3. *Remains in `ManualReviewRequested`* — manual review is awaited, not auto-approved

### Step 3: Observe the notification

Check the `notification-svc` logs:

```bash
kubectl logs -n radiusclaim-azure -l app=notification-svc --tail=100
```

**Expected log output (contains):**
```
ExpenseId: exp-<uuid2>
CorrelationId: <uuid2>
EventType: ManualReviewRequested
DecisionSource: ThresholdExceeded
Recipient: emp-demo-002@company.com
Subject: Your expense for $150.00 is pending manual review
Message: ...
OccurredAtUtc: 2026-03-24T14:35:10Z
```

**What this proves:**
- The `$150` expense did **not** auto-approve
- The workflow published a `ManualReviewRequested` event (distinct from `ExpenseRejected`)
- The notification service logged the manual-review notification
- The distinction between "hold for review" and "denied" is observable

---

## Observable Evidence Checklist

✅ **Auto-approve flow:**
- [ ] Expense submission returns `Submitted` status
- [ ] Poll shows progression: `Submitted` → `Approved` → `Reimbursed`
- [ ] Notification logs show `ExpenseApproved` event with correct `CorrelationId`
- [ ] Logs contain the `$50` amount and employee ID

✅ **Manual-review flow:**
- [ ] Expense submission returns `Submitted` status
- [ ] Poll shows progression: `Submitted` → `ManualReviewRequested`
- [ ] Status remains `ManualReviewRequested` (not auto-rejected or approved)
- [ ] Notification logs show `ManualReviewRequested` event with correct `CorrelationId`
- [ ] Logs contain the `$150` amount and employee ID

✅ **End-to-end traceability:**
- [ ] Same `CorrelationId` appears in submission response, workflow events, and notification logs
- [ ] `ExpenseId` is stable across all queries and logs
- [ ] Timestamps are UTC and consistent
- [ ] No logs show errors or timeouts

---

## Demo Timing

| Step | Time |
|------|------|
| Intro & setup (show slides) | 1 min |
| Submit $50 expense | 30 sec |
| Poll and observe approval + notification | 2–3 min |
| Submit $150 expense | 30 sec |
| Poll and observe manual-review hold + notification | 2–3 min |
| Show logs, highlight correlation | 1 min |
| Q&A | 1–2 min |
| **Total** | **~10 min** |

---

## Troubleshooting

### Submissions timeout or fail with 500

Check that the public entry service and internal workers are healthy:
```bash
kubectl get deployment,svc -n radiusclaim-azure
```

Expect: `expense-api`, `workflow-engine`, `notification-svc`, plus the `expense-api` service.

If the public gateway URL from `rad deploy` is not yet reachable, use the documented `kubectl port-forward` fallback and continue the demo from `http://127.0.0.1:8080`.

### Status remains `Submitted` and doesn't advance

The workflow may be slow to start. Wait 10–20 seconds between polls, or check workflow-engine logs:
```bash
kubectl logs -n radiusclaim-azure deployment/workflow-engine -c workflow-engine --tail=100
```

### Notifications don't appear in logs

Check that the pub/sub component is active:
```bash
kubectl get components -n radiusclaim-azure
```

Expect to see `pubsub` listed.

### Boundary case: exactly $100.00

A submission of exactly `$100.00` should trigger `ManualReviewRequested`, **not** auto-approval. This is the documented threshold decision.

---

## What This Demo Doesn't Cover

The following are intentionally out of scope for the ten-minute demo:

- **Real notifications** (email, Slack, Teams) — the sample logs notifications instead
- **Multi-tier approval** (e.g., manager review, finance review) — handled in Phase 8+
- **Expense rejection** (fraud, compliance denial) — the sample only shows auto-approve or manual-review holds
- **Reimbursement processing** — the workflow marks it done but does not integrate with a payments system
- **Audit logging** — logs are available but not aggregated in a dashboard
- **User authentication** — the demo uses static employee IDs

---

## Key Takeaways

1. **Dapr makes the workflow portable.** The same service code and workflow logic runs anywhere Dapr is available.
2. **Radius makes the infrastructure declarative.** The Kubernetes manifests and Dapr components are generated from the app model, not hand-authored.
3. **Azure-backed services stay behind Dapr abstractions.** The workflow uses `statestore` and `pubsub` by name; the actual backing (Blob Storage, Service Bus) is swappable via Radius recipes.
4. **The threshold is explicit.** < $100 auto-approves; >= $100 enters manual review — no ambiguous edge cases.
5. **Traceability is built in.** CorrelationId flows through every event, making the demo story traceable end-to-end.

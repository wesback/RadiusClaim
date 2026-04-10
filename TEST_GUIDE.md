# RadiusClaim Deployment Test Guide

## Overview

This guide provides comprehensive test scripts to diagnose deployment issues in RadiusClaim. When the application is running but not functioning correctly (expense submission fails, counters don't increment, workflows don't trigger), use these tests to isolate the root cause.

## Quick Start

Run the complete diagnostic suite:

```bash
cd /home/wesleyb/git/RadiusClaim
./scripts/deployment-readiness.sh
```

This runs all tests in sequence and provides a summary report.

## Individual Test Scripts

### 1. `health-check.sh` - Cluster & Component Status

**What it tests:**
- Kubernetes cluster connectivity
- Pod status (expense-api, workflow-engine)
- Dapr system components
- Dapr component CRDs (statestore, pubsub)

**When to run:** First, to verify basic infrastructure

```bash
./scripts/health-check.sh
```

**Expected output:**
- All pods running (not Pending, CrashLoopBackOff, etc.)
- Dapr operator and system components healthy
- Dapr components (statestore, pubsub) deployed

### 2. `api-endpoint-test.sh` - API Connectivity

**What it tests:**
- HTTP connectivity to expense-api service
- `/health` endpoint responds
- `/expenses` GET endpoint (if public)
- `/expenses` POST endpoint
- Port forwarding configuration

**When to run:** After health check passes

```bash
./scripts/api-endpoint-test.sh
```

**Expected output:**
- /health returns 200
- /expenses endpoints respond (200 or 401 for auth)
- Port forward successfully established

**Common issues:**
- If service port doesn't match pod port, check Radius configuration
- If endpoints return 401, authentication is configured (expected for secured APIs)

### 3. `dapr-component-test.sh` - State Store & Pub/Sub

**What it tests:**
- Dapr statestore component configuration
- State storage operations (set/get)
- Dapr sidecar health (localhost:3500)
- Pub/sub component connectivity
- Message publishing

**When to run:** After API test passes

```bash
./scripts/dapr-component-test.sh
```

**Expected output:**
- State operations succeed (set value, retrieve value)
- Dapr sidecar responds to health check
- Pub/sub publishes without error

**Common issues:**
- "AuthorizationFailure" → RBAC missing on Azure storage/service bus
- "TimeoutException" → Network/connectivity issue
- Component not found → Bootstrap phase 2 didn't run

### 4. `expense-submit-test.sh` - End-to-End Submission

**What it tests:**
- Complete expense submission workflow
- Initial state check
- POST /expenses with test data
- Expense persistence in state store
- Counter incrementation

**When to run:** After component tests pass

```bash
./scripts/expense-submit-test.sh
```

**Expected output:**
- Expense submission returns 201 or 200
- Expense appears in GET /expenses
- Counter increases in state store

**Common issues:**
- If POST returns 500 → Check API logs for unhandled exception
- If expense not stored → State store write failed
- If counter doesn't increase → POST handler doesn't increment counter

### 5. `workflow-trigger-test.sh` - Workflow Event Processing

**What it tests:**
- Workflow pod status and health
- Pub/sub topic configuration
- Event publishing to workflow
- Workflow subscription to events
- Workflow logs for processing activity

**When to run:** After submission test passes

```bash
./scripts/workflow-trigger-test.sh
```

**Expected output:**
- Published event returns 204/200 (no error)
- Workflow pod logs show event processing
- Workflow subscribed to expense.created topic

**Common issues:**
- Event published but not processed → Workflow not subscribed
- Workflow crashes with nil pointer → Dapr 1.17.3 async scheduling needed
- No workflow pod → Deployment may have failed

## Troubleshooting Flowchart

```
START: Application not working

├─ Run: health-check.sh
│  ├─ Pods not running? → Check `kubectl describe pod <pod>`
│  ├─ Components not deployed? → Re-run bootstrap (phase 2)
│  └─ Passed? Continue...
│
├─ Run: api-endpoint-test.sh
│  ├─ Service not found? → Check Radius deployment
│  ├─ Port mismatch? → Update service port in Radius
│  ├─ Endpoint returns 500? → Check API logs
│  └─ Passed? Continue...
│
├─ Run: dapr-component-test.sh
│  ├─ Authorization failure? → Assign RBAC roles (Storage Blob Data Contributor, etc.)
│  ├─ Component not found? → Re-run apply-dapr-components-from-recipes.sh
│  ├─ State operations fail? → Check Azure Storage connectivity
│  └─ Passed? Continue...
│
├─ Run: expense-submit-test.sh
│  ├─ POST returns 500? → Check API logs for exception
│  ├─ Expense not stored? → Check state store RBAC
│  ├─ Counter not incrementing? → Verify POST handler increments counter
│  └─ Passed? Continue...
│
├─ Run: workflow-trigger-test.sh
│  ├─ Event publish fails? → Check pub/sub component
│  ├─ Workflow not subscribed? → Restart workflow pod
│  ├─ Workflow crashes? → Check logs for errors, apply fixes
│  └─ Passed? SUCCESS
│
END: All tests passed
```

## Diagnostic Commands Reference

### View Logs

```bash
# Expense API pod logs
kubectl logs deployment/expense-api -n radiusclaim-azure-radiusclaim

# Expense API Dapr sidecar logs
POD=$(kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=expense-api -o name | head -1 | cut -d'/' -f2)
kubectl logs $POD -n radiusclaim-azure-radiusclaim -c daprd

# Workflow engine logs
POD=$(kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=workflow-engine -o name | head -1 | cut -d'/' -f2)
kubectl logs $POD -n radiusclaim-azure-radiusclaim

# Follow logs in real-time
kubectl logs -f deployment/expense-api -n radiusclaim-azure-radiusclaim
```

### Check Component Status

```bash
# List all Dapr components
kubectl get component -n radiusclaim-azure-radiusclaim

# Describe component
kubectl describe component statestore -n radiusclaim-azure-radiusclaim
kubectl describe component pubsub -n radiusclaim-azure-radiusclaim

# View full component YAML
kubectl get component statestore -n radiusclaim-azure-radiusclaim -o yaml
```

### Check Pod Status

```bash
# List all pods in namespace
kubectl get pods -n radiusclaim-azure-radiusclaim

# Describe pod in detail
kubectl describe pod <pod-name> -n radiusclaim-azure-radiusclaim

# Check pod events
kubectl describe pod <pod-name> -n radiusclaim-azure-radiusclaim | grep -A 20 "Events:"
```

### Port Forwarding

```bash
# Port forward to service
kubectl port-forward svc/expense-api 8080:80 -n radiusclaim-azure-radiusclaim

# Port forward to pod
POD=$(kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=expense-api -o name | head -1 | cut -d'/' -f2)
kubectl port-forward pod/$POD 8080:80 -n radiusclaim-azure-radiusclaim
```

## Known Issues & Solutions

### Issue: State Store RBAC Error

**Symptom:** Dapr logs show "AuthorizationFailure" or "403 Forbidden"

**Cause:** Managed identity missing roles on Azure Storage Account

**Solution:**
```bash
# Verify RBAC assignment
az role assignment list --scope /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{storage}

# If missing, add role (requires Owner on subscription)
az role assignment create --role "Storage Blob Data Contributor" \
  --assignee-object-id <managed-identity-id> \
  --scope /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{storage}
```

### Issue: Workflow Not Triggered

**Symptom:** Event published but workflow pod logs don't show processing

**Cause:** Workflow not subscribed to pub/sub topic

**Solution:**
```bash
# Restart workflow pod to force resubscription
kubectl rollout restart deployment/workflow-engine -n radiusclaim-azure-radiusclaim

# Wait for pod to restart
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=workflow-engine \
  -n radiusclaim-azure-radiusclaim \
  --timeout=60s
```

### Issue: Expense Counter Not Incrementing

**Symptom:** Expense submitted successfully but counter stays at 0

**Cause:** POST handler doesn't increment counter, or state store write fails

**Solution:**
```bash
# Check if API code increments counter
grep -n "expense-counter\|counter++" src/expense-api/Program.cs

# If missing, add counter increment logic to POST handler
# Verify state write succeeds (check dapr sidecar logs)
```

### Issue: API Port Mismatch

**Symptom:** Port-forward fails or service port doesn't match target port

**Cause:** Radius configuration mismatch between service definition and pod

**Solution:**
```bash
# Check what port the API is actually listening on
kubectl logs deployment/expense-api -n radiusclaim-azure-radiusclaim | grep -i "listen\|port"

# Update Radius app.bicep to match
# or update service port manifest
```

## Reporting Issues

When reporting deployment issues, provide:

1. **Output of health-check.sh**
2. **Output of the specific failing test**
3. **Pod logs** (`kubectl logs <pod> -n radiusclaim-azure-radiusclaim`)
4. **Component description** (`kubectl describe component <name> -n radiusclaim-azure-radiusclaim`)
5. **Recent commits** (what changed before it broke?)

Example bug report:

```
Expense submission fails with "The expense could not be submitted."

Test Results:
✓ health-check.sh passed
✓ api-endpoint-test.sh passed
✗ dapr-component-test.sh failed (state store write timeout)

API logs show:
  [ERR] Failed to write expense: timeout calling state store

Root cause: State store write timing out after 5s
Likely issue: Storage account RBAC or network connectivity
```

## Advanced Debugging

### Execute Commands Inside Pods

```bash
# Execute curl in pod (test state store directly)
POD=$(kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=expense-api -o name | head -1 | cut -d'/' -f2)
kubectl exec -it $POD -n radiusclaim-azure-radiusclaim -- bash

# Inside pod, test Dapr API
curl http://localhost:3500/v1.0/healthz
curl http://localhost:3500/v1.0/state/statestore/expense-counter
```

### Get Pod Metrics

```bash
# View resource usage
kubectl top pods -n radiusclaim-azure-radiusclaim

# Check for memory/CPU limits
kubectl get pods -n radiusclaim-azure-radiusclaim -o json | \
  jq '.items[] | {name: .metadata.name, resources: .spec.containers[].resources}'
```

### Check Azure Resources

```bash
# Verify storage account exists and is accessible
az storage account show --resource-group <rg> --name <storage>

# Check if blob container exists
az storage container list --account-name <storage>

# List service bus entities
az servicebus namespace show --resource-group <rg> --name <namespace>
```

## Next Steps

If all tests pass but application still doesn't work:

1. Check if there are unhandled exceptions in the API code
2. Verify OAuth/authentication is not blocking requests
3. Check if the UI is making correct API calls
4. Review recent code changes that might have broken functionality

If tests fail:

1. Use the troubleshooting flowchart above
2. Check the diagnostic commands for detailed error information
3. Consult the "Known Issues & Solutions" section
4. Contact the platform team with the test output

# RadiusClaim Deployment Test Checklist

Use this checklist to systematically diagnose deployment issues. Run tests in order from top to bottom.

---

## ✓ Pre-Test Setup

Before running tests, ensure:

- [ ] You have `kubectl` access to the cluster
- [ ] The RadiusClaim namespace exists: `kubectl get ns radiusclaim-azure-radiusclaim`
- [ ] You're in the `/home/wesleyb/git/RadiusClaim` directory
- [ ] All scripts in `scripts/` are executable: `chmod +x scripts/*.sh`

---

## Test 1: Health Check ✓
**Purpose:** Verify cluster connectivity and pod status
**Command:** `./scripts/health-check.sh`

### Expected Results
- [ ] Kubernetes cluster is accessible
- [ ] radiusclaim-azure-radiusclaim namespace exists
- [ ] Dapr operator is deployed
- [ ] Dapr API service exists
- [ ] expense-api service exists with target port configured
- [ ] expense-api pod is running
- [ ] Dapr sidecar is injected in expense-api pod
- [ ] workflow-engine pod exists and is running
- [ ] statestore component exists
- [ ] pubsub component exists

### If This Test Fails
- **Missing pods?** → Check pod events: `kubectl describe pod <pod-name> -n radiusclaim-azure-radiusclaim`
- **Components missing?** → Re-run bootstrap: `./scripts/apply-dapr-components-from-recipes.sh`
- **Namespace missing?** → Run: `./scripts/bootstrap.sh`

---

## Test 2: API Endpoint Test ✓
**Purpose:** Verify Expense API is responding to HTTP requests
**Command:** `./scripts/api-endpoint-test.sh`

### Expected Results
- [ ] expense-api pod found
- [ ] Service port identified (show target port in output)
- [ ] Port-forward established (PID shown)
- [ ] GET /health returns 200
- [ ] GET /expenses returns 200 (or 401/403 if auth is required)
- [ ] POST /expenses returns 201 or 200

### If This Test Fails
- **Port-forward fails?** → Check if pod is Running: `kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=expense-api`
- **/health returns non-200?** → Check API logs: `kubectl logs <expense-api-pod> -n radiusclaim-azure-radiusclaim`
- **POST returns 500?** → Check API logs for exception: `kubectl logs <expense-api-pod> -n radiusclaim-azure-radiusclaim | tail -50`
- **401/403 on authenticated endpoint?** → Expected if authentication is enabled

---

## Test 3: Dapr Component Test ✓
**Purpose:** Verify Dapr state store and pub/sub are working
**Command:** `./scripts/dapr-component-test.sh`

### Expected Results
- [ ] statestore component CRD exists
- [ ] pubsub component CRD exists
- [ ] Can set state value (expense-counter)
- [ ] Can retrieve state value (response contains "count")
- [ ] Can publish message to pub/sub
- [ ] Dapr sidecar is healthy (responds to /v1.0/healthz)

### If This Test Fails
- **statestore component missing?** → Run: `kubectl apply -f manifests/dapr-statestore.yaml -n radiusclaim-azure-radiusclaim`
- **State set/get fails?** → Check Azure Storage RBAC:
  ```bash
  az role assignment list --scope /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{storage}
  ```
  Add role if missing: `az role assignment create --role "Storage Blob Data Contributor" --assignee-object-id <mi-id>`
- **Pub/Sub fails?** → Check Service Bus RBAC (same as above, use "Azure Service Bus Data Sender" role)
- **Dapr sidecar unhealthy?** → Check Dapr logs: `kubectl logs <pod> -n radiusclaim-azure-radiusclaim -c daprd | tail -100`

---

## Test 4: Expense Submission Test ✓
**Purpose:** End-to-end expense submission (API → State Store)
**Command:** `./scripts/expense-submit-test.sh`

### Expected Results
- [ ] expense-api pod found
- [ ] Port-forward established
- [ ] Initial state checked (counter value shown)
- [ ] Expense submitted successfully (HTTP 200/201)
- [ ] GET /expenses returns 200
- [ ] Response contains expense data
- [ ] Final expense counter is populated

### If This Test Fails
- **Expense submission returns 500?** → Check API logs: `kubectl logs <expense-api-pod> -n radiusclaim-azure-radiusclaim`
- **Expense not appearing in GET?** → State store write may have failed, check Dapr sidecar logs: `kubectl logs <pod> -n radiusclaim-azure-radiusclaim -c daprd`
- **Counter not incrementing?** → Check if POST handler increments counter:
  ```bash
  grep -n "expense-counter\|counter\|increment" src/expense-api/Program.cs
  ```

---

## Test 5: Workflow Trigger Test ✓
**Purpose:** Verify workflows process expense events
**Command:** `./scripts/workflow-trigger-test.sh`

### Expected Results
- [ ] expense-api pod found
- [ ] workflow-engine pod found
- [ ] pubsub component exists
- [ ] Test event published successfully (HTTP 204/200)
- [ ] Workflow pod logs retrieved
- [ ] Workflow logs contain pub/sub subscription references

### If This Test Fails
- **workflow-engine pod not found?** → Deployment may have failed: `kubectl describe deployment workflow-engine -n radiusclaim-azure-radiusclaim`
- **Event publish fails?** → Check pub/sub component: `kubectl describe component pubsub -n radiusclaim-azure-radiusclaim`
- **Workflow doesn't process event?** → Restart workflow to force resubscription:
  ```bash
  kubectl rollout restart deployment/workflow-engine -n radiusclaim-azure-radiusclaim
  ```
- **Workflow crashes after restart?** → Check logs for errors: `kubectl logs <workflow-pod> -n radiusclaim-azure-radiusclaim | tail -100`

---

## Run All Tests Together

To run the complete diagnostic suite:

```bash
./scripts/deployment-readiness.sh
```

This will run all 5 tests in sequence and provide a summary.

---

## Failure Decision Tree

```
START: Application not working

├─ Run Test 1 (health-check.sh)
│  └─ FAIL → Pods not ready? Fix pod issues first
│
├─ Run Test 2 (api-endpoint-test.sh)
│  └─ FAIL → API not responding? Check container logs
│
├─ Run Test 3 (dapr-component-test.sh)
│  └─ FAIL → Components not working? Check RBAC & connectivity
│
├─ Run Test 4 (expense-submit-test.sh)
│  └─ FAIL → Submission fails? Check API exception handling
│
├─ Run Test 5 (workflow-trigger-test.sh)
│  └─ FAIL → Workflow not triggered? Check pub/sub wiring
│
└─ ALL PASSED → Check application business logic
```

---

## Useful Diagnostic Commands

### View Logs
```bash
# Expense API logs
kubectl logs deployment/expense-api -n radiusclaim-azure-radiusclaim

# Follow logs in real-time
kubectl logs -f deployment/expense-api -n radiusclaim-azure-radiusclaim

# Dapr sidecar logs
POD=$(kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=expense-api -o name | head -1 | cut -d'/' -f2)
kubectl logs $POD -n radiusclaim-azure-radiusclaim -c daprd

# Workflow engine logs
kubectl logs deployment/workflow-engine -n radiusclaim-azure-radiusclaim
```

### Check Status
```bash
# List all pods
kubectl get pods -n radiusclaim-azure-radiusclaim

# Describe a pod (events, conditions)
kubectl describe pod <pod-name> -n radiusclaim-azure-radiusclaim

# Check Dapr components
kubectl get component -n radiusclaim-azure-radiusclaim
kubectl describe component statestore -n radiusclaim-azure-radiusclaim
kubectl describe component pubsub -n radiusclaim-azure-radiusclaim
```

### Execute Commands in Pod
```bash
# Check Dapr sidecar from inside pod
POD=$(kubectl get pod -n radiusclaim-azure-radiusclaim -l app.kubernetes.io/name=expense-api -o name | head -1 | cut -d'/' -f2)
kubectl exec -it $POD -n radiusclaim-azure-radiusclaim -- bash

# Inside pod:
curl http://localhost:3500/v1.0/healthz          # Dapr health
curl http://localhost:3500/v1.0/state/statestore/expense-counter  # Get counter value
```

---

## When All Tests Pass

If all tests pass, the deployment infrastructure is working correctly. If the application still doesn't work, check:

1. **Business Logic:** Recent code changes that might have introduced bugs
2. **Authentication:** API may require valid credentials (token, API key)
3. **Configuration:** Check environment variables and secrets: `kubectl get configmap -n radiusclaim-azure-radiusclaim`
4. **UI:** Verify the frontend is making correct API calls (check browser console)

---

## Report Issues

When reporting deployment issues, include:

1. **Test output:** Copy-paste output from the failing test
2. **Pod logs:** `kubectl logs <pod> -n radiusclaim-azure-radiusclaim`
3. **Pod description:** `kubectl describe pod <pod> -n radiusclaim-azure-radiusclaim`
4. **Recent changes:** What was deployed/changed before it broke?

Example issue report:

```
Expense submission fails with "The expense could not be submitted"

Test Results:
✓ health-check.sh passed
✓ api-endpoint-test.sh passed
✗ dapr-component-test.sh failed: state store write timeout

Error from dapr logs:
  [ERR] Failed to set state: authorization failure

Root cause: Missing Storage Blob Data Contributor role on managed identity
```

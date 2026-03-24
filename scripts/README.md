# RadiusClaim - Scripts

This directory contains operational and validation scripts for RadiusClaim.

---

## Available Scripts

### `publish-radius-recipes.sh`

**Purpose:** Publish the repo's custom Radius recipes to an OCI registry before deploying an environment that references them.

**Usage:**
```bash
./scripts/publish-radius-recipes.sh <recipe-registry> <tag>
```

**Example:**
```bash
docker login ghcr.io
./scripts/publish-radius-recipes.sh ghcr.io/<your-org>/radiusclaim/recipes local
```

**Why it exists:**
- Radius recipe `templatePath` values must resolve to OCI-backed artifacts, not local relative files
- The script keeps the three custom recipes (`state-store`, `pubsub`, `secrets`) published under one teachable command
- GitHub Actions reuses the same script before deploying `infra/radius/environments/azure-radius.bicep`

### `validate-deployment.sh`

**Purpose:** End-to-end validation script for deployed RadiusClaim instances on Kubernetes.

**What it validates:**
- API health endpoint accessibility
- $50 auto-approve flow (complete state transitions)
- $150 manual-review flow (hold, not rejection)
- $100.00 boundary case (manual review, not auto-approval)
- Distributed system behavior (state, workflow, service invocation)

**Usage:**
```bash
./scripts/validate-deployment.sh <expense-api-base-url>
```

**Example (local port-forward for Kubernetes):**
```bash
# Set up port-forward to expense-api
kubectl port-forward -n radiusclaim-azure svc/expense-api 8080:8080 &

# Run validation against the forwarded port
./scripts/validate-deployment.sh http://127.0.0.1:8080
```

**Example (if expense-api has external ingress):**
```bash
./scripts/validate-deployment.sh https://expense-api.example.com
```

**Prerequisites:**
- `jq` installed (JSON processing)
- `curl` installed (HTTP requests)
- RadiusClaim deployed to Kubernetes and accessible (either via port-forward or external ingress)

**Output:**
- Colored pass/fail indicators for each check
- Summary of total checks passed/failed
- Exit code 0 on success, 1 on failure

**Use cases:**
- Post-deployment smoke test
- Manual validation before demo
- CI/CD integration (already integrated in `.github/workflows/deploy-azure.yml`)
- Troubleshooting deployment issues

**Optional CI artifact:**
- Set `VALIDATION_OUTPUT_PATH=/path/to/results.json` to capture expense and correlation IDs for downstream log checks
- The GitHub Actions workflow uses this to pair the shared flow validation with platform-specific notification evidence

**What this proves:**
- The sample demonstrates **meaningful distributed behavior**, not just process startup
- State persistence works across Dapr components
- Workflow orchestration executes correctly
- Service-to-service invocation delivers workflow requests
- Approval thresholds are implemented correctly
- Boundary case is handled as documented

---

## Adding New Scripts

When adding scripts to this directory:

1. **Use descriptive names:** `validate-*`, `deploy-*`, `troubleshoot-*`
2. **Add executable permission:** `chmod +x scripts/your-script.sh`
3. **Include usage documentation:** Header comment with purpose, usage, prerequisites
4. **Update this README:** Add entry in "Available Scripts" section
5. **Validate syntax:** Run `bash -n scripts/your-script.sh` before committing

---

## Script Conventions

- **Error handling:** Use `set -euo pipefail` for strict error handling
- **Output clarity:** Use colored output for pass/fail indicators
- **Exit codes:** 0 for success, non-zero for failure
- **Portability:** Bash 4.0+ compatible, avoid GNU-specific extensions
- **Documentation:** Clear usage message when run without arguments

---

## Integration Points

### GitHub Actions

The `validate-deployment.sh` script logic is integrated into `.github/workflows/deploy-azure.yml`:
- Run automatically after every deployment
- Reuses the same flow validation for the Kubernetes-first Radius path
- Uses `kubectl port-forward` plus `kubectl logs` after the shared script so the workflow stays valid across AKS, Arc-enabled / Azure Local, and self-managed Kubernetes clusters that meet Radius prerequisites
- Keeps the portability story honest: compute is Kubernetes-portable, but the current backing-service recipes remain Azure-specific
- Fails the workflow if validation does not pass

### Phase Gates

Validation scripts support phase gate approvals:
- Karen (Tester) runs scripts to validate phase completion
- Script output provides fresh evidence for gate reviews
- Pass/fail outcomes inform approval decisions

---

## Troubleshooting

### Script hangs during status polling

**Cause:** Service may be slow to start or networking issue  
**Solution:** Check workload health with `kubectl get deploy,pods -n <namespace>` and increase wait timeout if needed

### jq not found

**Cause:** jq not installed  
**Solution:** Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- Windows: Download from https://stedolan.github.io/jq/

### curl: Failed to connect

**Cause:** Incorrect URL or service not accessible  
**Solution:** Verify the expense-api URL or `kubectl port-forward` session, check cluster networking rules, and confirm the service is running

### All checks fail with "Failed to reach health endpoint"

**Cause:** Service not deployed or networking issue  
**Solution:** 
1. Verify deployment completed: `kubectl get deployment expense-api -n <namespace>`
2. Check service exposure: `kubectl get svc expense-api -n <namespace>` and port-forward if needed
3. Test health endpoint manually: `curl http://127.0.0.1:8080/healthz` (or your cluster-specific URL)

---

## References

- Phase 7 Validation Checklist: [`docs/phase-7-validation-checklist.md`](../docs/phase-7-validation-checklist.md)
- Demo Walkthrough: [`docs/phase-7-demo-walkthrough.md`](../docs/phase-7-demo-walkthrough.md)
- GitHub Actions Workflow: [`.github/workflows/deploy-azure.yml`](../.github/workflows/deploy-azure.yml)

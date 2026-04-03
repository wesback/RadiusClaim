# Portability Validation Tests

This directory contains automated tests that validate the RadiusClaim codebase adheres to the portability paradigm.

## Philosophy

The portability paradigm ensures:

1. **App code is cloud-agnostic** — Services use Dapr abstractions, not direct Azure SDK calls
2. **Recipes are self-contained** — Infrastructure recipes can deploy standalone without manual intervention
3. **Bootstrap is idempotent** — Deployment scripts can be re-run safely
4. **Deployment is region-agnostic** — Moving to a different region requires only parameter changes
5. **Dapr components are available** — Required Dapr building blocks are properly configured

## Test Suite

### 1. `app-no-azure-hardcoding.sh`

**What it validates:**
- App code contains no hardcoded Azure subscriptions, resource groups, or regions
- App code uses Dapr abstractions instead of direct Azure SDK usage
- No hardcoded connection strings in code

**How to run:**
```bash
bash tests/portability/app-no-azure-hardcoding.sh
```

**What a failure means:**
Your application code is tightly coupled to Azure specifics. Refactor to use Dapr building blocks (state, pubsub, secrets) instead of direct Azure SDK calls.

---

### 2. `recipes-are-complete.sh`

**What it validates:**
- All Radius recipes have required `param context object`
- Recipes expose outputs for connection information
- Recipes use parameterized locations (not hardcoded)
- Core recipes exist (state-store, pubsub, secrets)
- Metadata files (.json) exist for each recipe

**How to run:**
```bash
bash tests/portability/recipes-are-complete.sh
```

**What a failure means:**
Your Radius recipes are incomplete or won't work properly with the Radius environment. Fix missing parameters, outputs, or metadata files.

---

### 3. `bootstrap-idempotency.sh`

**What it validates:**
- Bootstrap script has existence checks before creating resources
- Conditional execution patterns are present
- Prerequisites are checked before running

**How to run:**
```bash
bash tests/portability/bootstrap-idempotency.sh
```

**What a failure means:**
Running `bootstrap.sh` multiple times may cause failures or duplicate resources. Add conditional logic to check if resources exist before creating them.

**Note:** This test performs static analysis only. Full idempotency verification requires running bootstrap twice on a real cluster.

---

### 4. `region-agnostic.sh`

**What it validates:**
- Infrastructure files use parameterized locations
- Radius environments expose location parameters
- Recipes use `context.azure.location` or parameters
- Scripts support location configuration via environment variables

**How to run:**
```bash
bash tests/portability/region-agnostic.sh
```

**What a failure means:**
Deploying to a different Azure region will require code changes. Parameterize all location references to support multi-region deployments.

---

### 5. `dapr-components-loaded.sh`

**What it validates:**
- Required Dapr components exist in the cluster namespace
- Components are of the expected type (state, pubsub, secretstore)

**How to run:**
```bash
bash tests/portability/dapr-components-loaded.sh [namespace]
# Default namespace: azure-radiusclaim
```

**What a failure means:**
Dapr components are missing or misconfigured in your cluster. Run `scripts/deploy-dapr-components.sh` to install them.

**Note:** This test requires a running Kubernetes cluster with deployed components. It will skip gracefully if cluster is not available.

---

## Running All Tests

To run the complete validation suite:

```bash
bash tests/portability/run-all.sh
```

This will execute all tests and provide a summary report.

## CI/CD Integration

Add this to your CI pipeline to prevent portability regressions:

```yaml
- name: Validate Portability
  run: bash tests/portability/run-all.sh
```

## Interpreting Results

- ✅ **PASS** — Test passed, no issues found
- ❌ **FAIL** — Test failed, action required to fix
- ⚠️ **WARNING** — Potential issue detected, manual review recommended

## When to Run

- **Before committing** — Ensure your changes don't break portability
- **In CI/CD** — Prevent portability regressions from merging
- **Before release** — Verify the codebase is deployment-ready
- **After infrastructure changes** — Validate recipes and configurations

## Troubleshooting

If a test fails:

1. Review the detailed output from the failing test
2. Run the individual test script for focused debugging
3. Check the test's "What a failure means" section in this README
4. Fix the identified issues
5. Re-run the test to verify the fix

## Adding New Tests

When adding a new portability test:

1. Create a new `.sh` file in this directory
2. Follow the existing pattern (exit 0 on pass, exit 1 on fail)
3. Add descriptive output with ✅/❌ prefixes
4. Update `run-all.sh` to include your test
5. Document the test in this README

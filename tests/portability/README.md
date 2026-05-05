# Portability Validation Tests

This directory contains automated tests that validate the RadiusClaim codebase adheres to the portability paradigm.

## Philosophy

The portability paradigm ensures:

1. **App code is cloud-agnostic** — Services use Dapr abstractions, not direct Azure SDK calls
2. **Recipes publish the live contract** — Bootstrap and Dapr component projection consume current Radius outputs/metadata
3. **Bootstrap is idempotent** — Deployment scripts can be re-run safely and keep the `platform-secrets` contract intact
4. **Deployment is region-agnostic** — Moving to a different region requires only parameter changes
5. **Dapr components are available** — Required Dapr building blocks are projected from Radius recipes into the workload namespace

## Test Suite

### 1. `app-no-azure-hardcoding.sh`

**What it validates:**
- App code contains no hardcoded Azure subscriptions, resource groups, or regions
- App code uses Dapr abstractions instead of direct Azure SDK usage
- No hardcoded connection strings in code
- `infra/radius/app.bicep` does not bake in raw in-cluster service URLs such as `http://expense-api:8080`

**How to run:**
```bash
bash tests/portability/app-no-azure-hardcoding.sh
```

**What a failure means:**
Your application code is tightly coupled to Azure specifics. Refactor to use Dapr building blocks (state, pubsub, secrets) instead of direct Azure SDK calls.

---

### 2. `recipes-are-complete.sh`

**What it validates:**
- All Azure Radius recipes have the required `param context object`
- Recipes publish both `values` and `resourceMetadata` outputs
- `resourceMetadata.dapr` includes component name/type/version/metadata for bootstrap projection
- Recipes keep the current contracts for PostgreSQL state, Service Bus pub/sub, and Key Vault `platform-secrets`
- Recipes rely on Radius-managed `outputResources` instead of stale explicit `output resources`

**How to run:**
```bash
bash tests/portability/recipes-are-complete.sh
```

**What a failure means:**
Your Radius recipes drifted from the current bootstrap/component projection contract. Fix missing outputs or stale Dapr metadata.

---

### 3. `bootstrap-idempotency.sh`

**What it validates:**
- Bootstrap script has existence checks before creating resources
- Bootstrap refreshes Dapr components through `scripts/apply-dapr-components-from-recipes.sh`
- Bootstrap still verifies `statestore`, `pubsub`, and `platform-secrets`
- Bootstrap resolves Key Vault data for `platform-secrets` from Radius metadata, with the `kvrc` fallback intact
- Prerequisites and re-run guards are still present

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
- Azure-backed Radius environments expose location parameters
- Azure recipes keep location inputs parameterized
- Scripts support location configuration via environment variables
- `local.bicep` is treated as intentionally non-Azure and does not generate stale warnings

**How to run:**
```bash
bash tests/portability/region-agnostic.sh
```

**What a failure means:**
Deploying to a different Azure region will require code changes. Parameterize all location references to support multi-region deployments.

---

### 5. `dapr-components-loaded.sh`

**What it validates:**
- Static contract: bootstrap uses `scripts/apply-dapr-components-from-recipes.sh` and that script reads live `resourceMetadata.dapr`
- Live cluster (when available): required Dapr components exist in the workload namespace
- Live components expose the expected Azure-backed types and key metadata (`actorStateStore`, `keyPrefix`, `namespaceName`, `vaultName`)

**How to run:**
```bash
bash tests/portability/dapr-components-loaded.sh [namespace]
# Default environment namespace: radiusclaim-azure
```

**What a failure means:**
Dapr components are missing or misconfigured in your cluster. Refresh them with `scripts/apply-dapr-components-from-recipes.sh` (bootstrap uses the same flow).

**Note:** Static contract checks always run. Live CRD verification exits as **SKIP** when a cluster or deployed namespace is not available.

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
- ⏭️ **SKIP** — Static checks passed, but a live cluster-dependent check could not run
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

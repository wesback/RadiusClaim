# Decisions Registry

**Last Updated:** 2026-03-25T11:31:49Z

---

## 1. Full Codebase Review — Opus 4.6 Deep Audit

**By:** Daisy (Lead)  
**Date:** 2026-03-24  
**Status:** FINDINGS DOCUMENTED — action required

### Summary

Conducted a full-depth architectural review of the entire RadiusClaim codebase: all source code (17 files), all infrastructure (Radius bicep, recipes, environments, local Dapr configs, scripts), all documentation (README, docs/*.md), and the CI/CD workflow. Used Opus 4.6 model for depth.

### Critical Findings (7 total — must fix before demo)

#### Infrastructure
1. **`Radius.Compute/*` resource types may not exist in stock Radius 0.55** — `app.bicep` and `container-service.bicep` use `Radius.Compute/containers` and `Radius.Compute/routes` with API version `2025-08-01-preview`. Standard Radius 0.55 uses `Applications.Core/containers` and `Applications.Core/httpRoutes`. If targeting a custom preview build, document it explicitly. Otherwise, `rad deploy` will fail.
2. **Pub/sub recipe outputs wrong Dapr component type** — Recipe outputs `pubsub.azure.servicebus` (queues), but the ACA bootstrap and app logic expect `pubsub.azure.servicebus.topics`. Messages won't flow through recipe-provisioned path.
3. **State store version mismatch** — ACA bootstrap uses v2, recipe outputs v1. Breaking schema differences between versions.

#### Documentation
4. **README project tree shows `sovereignapp/` not `RadiusClaim/`** — Stale name from prior incarnation.
5. **README Contracts path wrong** — Shows `src/RadiusClaim.Contracts/` but actual path is `src/shared/RadiusClaim.Contracts/`.
6. **`dev.bicep` mislabeled as "Local Radius environment"** — It provisions Azure-backed recipes, not local Redis. Breaks portability narrative.

#### CI/CD
7. **`deploy-azure.yml` has no `azure/login` step** — Workflow sets OIDC permissions but never authenticates. `rad credential register azure` will fail without ambient Azure credentials.

### Important Findings (11 total — should fix for credibility)

#### Code
- `BuildNotification` throws on `ExpenseRejected` — latent crash when rejection logic is added
- `ApproveExpenseActivity` idempotency guard is too narrow (only handles auto-approved + Reimbursed)
- `ExpenseRejected` record and `Rejected` status are dead contracts — no code path produces them
- `DaprClient.CreateInvokeHttpClient` bypasses DI-configured client endpoint

#### Infrastructure
- No local Dapr secret store component — `platform-secrets` reference in `app.bicep` will fail local `dapr run`
- `dev.bicep` uses `resourceGroup().id` default — won't resolve in `rad deploy`
- `azure-radius.parameters.json` is incomplete (missing required params)
- Key Vault recipe lacks purge protection (7-day vs 90-day retention)
- Recipe auth uses shared keys while ACA bootstrap uses managed identity

#### Documentation/CI
- README "Quick Start (Local Dev)" still says "Coming in Phase 2" — we're in Phase 7
- `dotnet test` in CI is vacuous — zero test projects exist, green badge is misleading
- Stale `ghcr.io/sovereignapp/radiusclaim` default registry in `app.bicep` and params files

### Recommended Action Sequence (Risk-Ordered)

1. **Infrastructure API compatibility** (Daisy/Platform) — Confirm Radius version or update resource types
2. **Pubsub type fix** (Daisy/Platform) — Change recipe output to `pubsub.azure.servicebus.topics`
3. **State store alignment** (Daisy/Platform) — Unify recipe v1 or bootstrap v2
4. **Registry update** (Billy/CI) — Replace `sovereignapp` with `wesback` in app.bicep, params, and CI workflows
5. **README and docs cleanup** (Eddie/Docs) — Correct tree, paths, and Quick Start status
6. **Code contract cleanup** (Graham/Core Dev) — Remove dead code; wire `ExpenseRejected` handling
7. **Local Dapr config** (Graham/Core Dev) — Add secret store component for `dapr run`

### Next Step

Awaiting consensus on priority sequence.

---

## 2. Remove misleading namespace defaults; teach discovery pattern

**Date:** 2026-03-25  
**Author:** Eddie (Docs/Story)  
**Status:** Completed  

### Problem

The image pull secret creation docs used a harmful fallback pattern:
```bash
export RADIUS_KUBERNETES_NAMESPACE="${RADIUS_KUBERNETES_NAMESPACE:-default}"
```

This silently defaulted to "default" namespace, which is dangerous because:
- Radius maps group names (e.g., "radiusclaim-group") to Kubernetes namespaces automatically
- First-time users had no visibility into which namespace would be created
- Errors only appeared *after* the user ran the kubectl commands
- It violated the team's earlier decision (2026-03-24) that namespace changes should be direct string updates, not hidden compatibility logic

### Solution

**Remove the fallback entirely. Teach discovery instead.**

1. **Discovery step** (`kubectl get namespaces | grep -i radius`): Users see what actually exists
2. **Clear naming**: Document the relationship "group name → namespace name"
3. **Explicit assignment**: Users set `RADIUS_KUBERNETES_NAMESPACE` to their actual group name before copy/pasting

### Implementation

- **docs/end-to-end-setup-walkthrough.md** (lines 360–379):
  - Added discovery command before the secret creation
  - Removed `-default` fallback
  - Showed how group name determines namespace

- **docs/radius-validation-checklist.md** (lines 34–35, 76–86):
  - Updated cluster verification to discover namespaces
  - Removed hard-coded default from variable guidance
  - Added explanation: "discover it by running `kubectl get namespaces | grep -i radius`"

### Rationale

**Why discovery over defaults?**
- Namespace is infrastructure metadata users must own. Guessing it is worse than asking.
- `kubectl get namespaces` is a skill first-time users should learn anyway.
- The team's namespace migration decision (3/24) emphasizes direct, transparent config changes, not silent fallbacks.

**Why still allow override?**
- Advanced users may run multiple Radius groups in one cluster.
- Keeping `RADIUS_KUBERNETES_NAMESPACE` as an optional variable respects that flexibility.

### Alignment with Prior Decisions

- Aligns with 2026-03-24 namespace migration decision: "no compatibility code that supports both old and new namespaces"
- Consistent with the team's emphasis on explicit, auditable configuration
- Reduces support burden: errors are caught at kubectl discovery, not at pod creation

### Copy-Paste Safety

✅ Users must now:
1. Discover their namespace: `kubectl get namespaces | grep -i radius`
2. Replace the example value: `export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-group"`
3. Understand the mapping before running the rest of the code

This is more hands-on but safer and more transparent than silent defaults.

---

## 3. AKS docker_bridge_cidr Warning Resolution

**Date:** 2026-03-25  
**Raised by:** Eddie (Docs/Story)  
**Status:** Resolved — No action required for RadiusClaim

### Problem

User reported warning: `docker_bridge_cidr is not a known attribute of class azure.mgmt.containerservice.models._models_py3.ContainerServiceNetworkProfile and will be ignored when running the az aks create`.

### Investigation

Checked Azure Learn documentation (Microsoft Learn MCP):
- `docker_bridge_cidr` exists in PowerShell, JavaScript, and ML SDKs as a valid property
- **Python `azure-mgmt-containerservice` SDK does NOT expose it** in current version
- SDK version mismatch: API-level property vs. Python client binding limitation
- AKS CLI equivalent is `--docker-bridge-address` (takes IP address like `172.17.0.1/16`)

### Resolution

1. **This warning is SDK-scoped; code is safe.** RadiusClaim does not use `docker_bridge_cidr` anywhere (searched all `.py`, `.sh`, `.yaml`, `.bicep`, `.tf` files).

2. **If property is needed in future:** Upgrade `azure-mgmt-containerservice` to a newer release that includes the attribute, or use CLI parameter instead.

3. **Docs note:** No documentation updates needed—property was never exposed in RadiusClaim's AKS deployment workflows.

### Recommendation

No code changes. If encountered in external scripts or CI/CD:
- Replace `docker_bridge_cidr` with `--docker-bridge-address` in CLI calls
- Or remove entirely and let Azure auto-assign the bridge address (safe for most clusters)

---

## 4. README Disclaimer: Sample Code Status

**Decided:** Add a concise, practical disclaimer to README.md clarifying RadiusClaim is sample/reference code, not production-ready.

### Placement
- **Location:** Between the intro tagline and the "The Problem" section
- **Rationale:** First-time readers encounter it immediately after understanding what the repo is, before diving into the narrative. Early visibility without being alarmist.

### Content
```
> **Note:** This is sample code for learning and reference. It is not production-ready. Use it to understand patterns; adapt it for your production requirements, security posture, and testing standards.
```

### Tone Alignment
- Practical, direct voice matching the existing README
- Constructive: frames it as "learn patterns, then adapt" rather than "do not use"
- Specific: calls out real concerns (security posture, testing standards)
- Not verbose: fits the visual rhythm of the blockquote header

### Why This Works
- Uses blockquote formatting (matches the existing tagline style)
- Placed in the established "separator + intro" flow
- Acknowledges the value of the code while being clear about its limitations
- Readers see it early and understand context before reading detailed sections

---

## 5. Live Cluster Recovery Commands (Reference Documentation)

**Date:** 2026-03-25  
**Author:** Graham (Platform Dev)  
**Status:** Documented for team reference

### Context

AKS cluster (`radiusclaim-azure-radiusclaim`) has three deployments stuck in `Pending`:
- Stale image sources: `ghcr.io/sovereignapp/radiusclaim:{phase1,latest}` (private, incorrect)
- No Dapr components in the namespace
- Image pull failures (`403 Forbidden`) on private GHCR packages
- daprd sidecars failing due to inability to fetch app images

### Recovery Strategy (Reference Only)

**Part 1: Image Registry Access** — Choose one:
- **Option A:** Make `ghcr.io/wesback/radiusclaim` packages PUBLIC (recommended for public sample)
- **Option B:** Add `imagePullSecret` to AKS for GHCR private access (if packages must stay private)

**Part 2: Redeploy** — Scale down, update images, scale up:
- Use `kubectl scale` and `kubectl set image` to swap container images
- Redeploy with `ghcr.io/wesback/radiusclaim:<TAG>`

**Part 3: Dapr Components** — Verify or recreate:
- Check if Dapr components exist: `kubectl get components -n radiusclaim-azure-radiusclaim`
- If missing, re-run `rad deploy` to provision environment and components

### Operator Follow-up

- Choose and execute Part 1 option first (image registry access)
- Complete Part 2 redeploy
- Verify Part 3 Dapr components
- Validate all pods reach Running state and expected image pull succeeds

### Notes

- **Radius ownership:** Dapr components are IaC-owned by Radius, not manually created
- **Image updates:** CI/CD workflow does exactly this—builds, tags with SHA, then `rad deploy` with imageTag. For one-off recovery, use `kubectl set image` directly.
- **Private vs. public:** Public sample → Option A (make public). Production → Option B (imagePullSecret).

---

## 6. GHCR Pull Secret Sequencing — Eddie

**Date:** 2026-03-25  
**Owner:** Eddie (Docs/Story)  
**Status:** Applied  
**Scope:** Documentation updates for pull secret creation timing

### Problem

Users attempting to follow the setup walkthrough encountered this error:
```
error: failed to create secret namespaces "radiusclaim-azure" not found
```

The docs instructed pull secret creation before the namespace existed.

### Decision

**Pull secrets must be configured AFTER the Radius environment is deployed.**

#### Details

1. **When:** Step 8a (after `rad deploy infra/radius/environments/azure-radius.bicep`), not Step 6
2. **Why:** The namespace `radiusclaim-azure` is created by the environment deployment itself
3. **Where:** New optional Step 8a in the walkthrough; added to validation checklist troubleshooting
4. **Explicit defaults:** Docs now state the actual namespace from the bicep (`radiusclaim-azure`), not imply a derived one

#### Files Updated

- `docs/end-to-end-setup-walkthrough.md`
  - Step 6: Removed premature pull secret commands; added warning and forward reference
  - Step 8a: New optional step for configuring pull secrets after environment deploy
  
- `docs/radius-validation-checklist.md`
  - Pull secret troubleshooting: Clarified namespace sequencing and explicit defaults

### Implication for Other Agents

- **Graham (Infrastructure):** No changes to the bicep or environment behavior
- **Raj (Platform):** No changes to deployment scripts (already ordered correctly)
- **All:** When docs reference "the namespace," prefer explicit names from the platform (e.g., `radiusclaim-azure` from the bicep) over inferred or fallback names

### Related Context

- `infra/radius/environments/azure-radius.bicep` line 7: `param kubernetesNamespace string = 'radiusclaim-azure'`
- Earlier decision (2026-03-25): Namespace guidance should be discovery-based, not guessed defaults

---

## 7. Keep Azure Radius namespace default explicit — Graham

**Date:** 2026-03-25  
**Owner:** Graham (Platform Dev)  
**Status:** Applied  

### Decision

Keep the Azure Radius environment namespace default explicit as `radiusclaim-azure`.

Do **not** remove the default and do **not** change the docs to describe it as derived from the Radius group name.

### Why

- `infra/radius/environments/azure-radius.bicep` is the authoritative platform contract for the Azure-backed Kubernetes slice, and it already defaults `kubernetesNamespace` to `radiusclaim-azure`.
- `infra/radius/environments/azure-radius.parameters.json`, `.github/workflows/deploy-azure.yml`, and the broader operator story already align on that explicit default.
- Our standing platform rule is to keep namespace changes as direct environment-default updates, not add more glue or derive behavior from unrelated concepts such as the Radius group name.
- The reported failure (`namespaces "radiusclaim-azure" not found`) is an ordering problem in the walkthrough, not evidence that the default is wrong.

### Platform Truth

- The Kubernetes namespace for this environment does **not** exist before the Azure Radius environment deploy runs.
- The namespace is created by deploying `infra/radius/environments/azure-radius.bicep`, because the environment contract sets `properties.compute.namespace` to `kubernetesNamespace`.
- Any step that writes Kubernetes objects into that namespace (for example the GHCR pull secret) must happen **after** the environment deployment, unless the step explicitly creates the namespace first.

### Guidance for Eddie / Docs

- Say the optional `RADIUS_KUBERNETES_NAMESPACE` override defaults to `radiusclaim-azure`.
- Remove wording that says the namespace is derived from the Radius group name.
- Keep the pull-secret instructions after environment deployment, and explain that the environment deployment is what creates the namespace.
- If docs show an override example, make it clear the same overridden value must be passed to the environment deploy and then reused for later `kubectl` commands.

### Repo Action

- No infra default change required.
- The safe fix is documentation/order clarity, not a platform-model change.

### Validation

- `az bicep build --file infra/radius/environments/azure-radius.bicep` ✅
- `dotnet test RadiusClaim.slnx` ✅

---

## 8. Key Vault Soft-Delete Collision Resolution

**Date:** 2026-03-25  
**Owner:** Graham (Platform Dev)  
**Status:** DECISION  

### Problem

Radius `rad deploy` fails with soft-delete collision:
```
failed to deploy recipe azure-keyvault-secrets because a vault with the same name 
already exists in deleted state [Microsoft.KeyVault/vaults/ce-ghhsgdsk4etcc]
```

### Root Cause

**Not an app-model bug.** This is Azure Key Vault soft-delete behavior:

1. Radius `app.bicep` generates vault names deterministically via `uniqueString(applicationName, environment, 'platform-secrets')`
2. When deleted, Key Vaults enter a **7-day soft-delete period**
3. Within this window, vault names are **reserved** — cannot create new vaults with that name
4. After retention, Azure **automatically purges** the vault

### Solution: Three Operator Paths

#### Option A: Wait for Auto-Purge (Recommended)
- Vault `ce-ghhsgdsk4etcc` auto-purges on **2026-04-01 15:22:30 UTC**
- Zero risk; aligns with Azure defaults
- Steps: Check purge date with `az keyvault list-deleted`, retry deployment after date passes

#### Option B: Force New Vault Name (Timeline-Critical)
- Create new Radius environment with different name (forces new `uniqueString` hash)
- ```bash
  rad env create <new-environment-name> --namespace radiusclaim-azure
  rad deploy --environment <new-environment-name> --from ./infra/radius/app.bicep --parameters imageTag=<TAG>
  ```
- Lower risk than Option C

#### Option C: Manual Purge (Not Recommended)
- ```bash
  az keyvault purge --name ce-ghhsgdsk4etcc --location <region>
  ```
- High risk; use only if Option A timeline unacceptable

### Prevention: Code-Level Fix (Future)

Add optional `recoverDeletedVault` parameter to `recipes/azure/secrets.bicep`:

```bicep
param recoverDeletedVault bool = false

resource recoveryStep 'Microsoft.KeyVault/vaults/recover@2023-07-01' = if (recoverDeletedVault) {
  // recovery logic
}
```

Gives operators explicit control over soft-delete collision handling.

### Decision

**Recommended:** Option A (wait for auto-purge). Zero operator risk.  
**If timeline-critical:** Option B safer than Option C.  
**For future deployments:** Document soft-delete behavior in operator runbooks and validation checklist.

### Files Updated

- `docs/radius-validation-checklist.md` — Added soft-delete troubleshooting section

---

## 12. Log Triage: Expense API Readiness

**By:** Billy (Backend Dev)  
**Date:** 2026-03-25  
**Status:** ANALYSIS COMPLETE — platform action required

### Observation

Expense API pod logs show `state store statestore is not configured` on every state operation.

### Root Cause (Single Most Likely)

**Platform wiring issue: Dapr statestore component is not provisioned or not mounted in the expense-api sidecar configuration.**

Evidence:
1. Dapr sidecar binary running and initialized cleanly (312ms init time)
2. Dapr can reach placement service, scheduler, actors subsystem
3. gRPC error `StatusCode="FailedPrecondition"` with `Detail="state store statestore is not configured"` thrown by Dapr runtime when app tries to access component named `statestore` that does not exist
4. App code calls `GetStateAsync(RadiusClaimDapr.Components.StateStore, ...)` where `StateStore = "statestore"` — hardcoded component name
5. No app-code bug would cause this; error is caught and surfaced as 503
6. Workflow engine has no error logs — either doesn't need statestore in startup, or Radius/AKS deployment wired differently

### Verdict

| Dimension | Verdict |
|-----------|---------|
| App code | ✓ Correct — error caught and surfaced as 503 |
| Stale browser state | ✗ Not the issue — fresh logs show service consistently unavailable |
| Workflow-engine behavior | ✓ Healthy — no errors, initialized cleanly |
| **Platform wiring** | ✗ **FAULT** — Dapr statestore component missing from expense-api sidecar |

### Next Action

Verify Radius/AKS deployment for expense-api Dapr sidecar configuration:
1. Check Dapr component definition (YAML or Bicep resource named `statestore`)
2. Confirm mounted in `expense-api` namespace and visible to Dapr runtime
3. Verify backing store reachability (Redis, Cosmos DB, etc.)

Until statestore component available, `GET /expenses`, `POST /expenses`, and workflow lookups remain inaccessible.

---

## 13. Dapr Component Projection Gap and Recovery Strategy

---
**Decision Date:** 2026-03-25  
**Author:** Graham (Platform Dev)  
**Status:** IMPLEMENTED  
**Affects:** deployment, recipes, documentation

### Problem

Radius recipes with `resourceProvisioning: 'recipe'` provision Azure backing resources (Storage, Service Bus, Key Vault) but **do NOT automatically project Kubernetes Dapr Component objects**. This is fundamentally different from `resourceProvisioning: 'manual'` mode, which does project components.

#### Root Cause
- Radius `Applications.Dapr/*` resources with recipe-based provisioning create Azure infrastructure only
- Radius controller does not translate recipe outputs into Kubernetes `Component` CRDs
- Services fail with `state store statestore is not configured` because Dapr sidecars have no component definitions

#### Secondary Issue Discovered
State-store recipe configures storage account without `allowSharedKeyAccess: true`, causing authentication failures even after manual component projection.

### Solution Implemented

**1. Manual Component Deployment Script**  
Created `scripts/deploy-dapr-components.sh` that:
- Extracts recipe parameters from Radius resources
- Fetches Azure credentials (storage keys, Service Bus connection strings)
- Creates Kubernetes secrets
- Generates and applies Dapr Component manifests
- Handles namespace auto-detection

**2. Template Component File**  
Created `infra/kubernetes/dapr-components.yaml` as reference template for manual deployment.

### Recovery Sequence for Operators

**CRITICAL BLOCKER:** Storage account created by recipe has `allowSharedKeyAccess: false` and this setting cannot be changed post-creation (enforced by Azure Policy). Component deployment script will create components, but Dapr will fail to initialize them.

#### Only Viable Path (Requires Recipe Fix)

```bash
# Step 1: Update recipe to allow shared key access
# Edit infra/radius/recipes/azure/state-store.bicep
# Add allowSharedKeyAccess: true to storageAccount properties

# Step 2: Rebuild and republish recipe
./scripts/publish-radius-recipes.sh

# Step 3: Redeploy entire Radius application
rad app delete radiusclaim --yes
rad deploy infra/radius/app.bicep -p imageTag=<tag>

# Step 4: Deploy Dapr components
./scripts/deploy-dapr-components.sh --resource-group "radiusclaim-rg"

# Step 5: Verify components loaded
kubectl logs -n radiusclaim-azure-radiusclaim deployment/expense-api -c daprd --tail=20 | grep "Component loaded"
```

### Long-Term Fix Required

**Option 1: Fix the Recipe (Preferred)**  
Update state-store recipe to include `allowSharedKeyAccess: true` in storage account properties.

**Option 2: Use Managed Identity (Best Practice)**  
Configure pods with Azure workload identity; update Dapr component to use `azureClientId` instead of `accountKey`.

**Option 3: Radius Feature Request**  
File issue with Radius project requesting automatic Dapr Component projection from recipe outputs.

### Verdict

TWO separate issues:

1. **Component Projection Gap (Radius Behavior):** Recipes do not automatically project Dapr Component objects. Workaround implemented; recipe fix required.
2. **Storage Account Auth Misconfiguration (Recipe Bug):** State-store recipe missing `allowSharedKeyAccess: true`. **BLOCKS DEPLOYMENT** — requires recipe fix before initial deployment.

---

## 14. Dapr Component Wiring Gap in Radius Recipe Output

**Date:** 2026-03-25  
**Agent:** Graham (Platform Dev)  
**Status:** REQUIRES ACTION

### Summary

Cluster log triage reveals **platform wiring gap, not Dapr or app misconfiguration**: Radius recipes have successfully provisioned Azure Blob Storage backing resources and applications are running healthy, but the Dapr Component resource (Kubernetes object) for statestore is missing from radiusclaim-azure namespace.

### Evidence

✅ **Healthy signals:**
- Both expense-api and workflow-engine pods running and registered with Dapr placement service
- Dapr sidecars initialized cleanly (312–319ms init time)
- Workflow engine and actors framework active
- gRPC endpoints to Dapr runtime established

❌ **The blocker:**
- Repeated Dapr gRPC failures: `Status(StatusCode="FailedPrecondition", Detail="state store statestore is not configured")`
- Apps crash when attempting state operations
- Dapr reports "actors: state store is not configured" at INFO level

### Root Cause

**Hypothesis:** Radius `statestore` resource in `app.bicep` uses `resourceProvisioning: 'recipe'` to invoke Azure Blob recipe, which correctly creates Storage account and container. However, **Dapr Component resource** (Kubernetes object telling Dapr sidecars how to find and authenticate to statestore) is either:
1. Not emitted by recipe's output binding, or
2. Not being applied to namespace by Radius after recipe execution

**Location of wiring:** Gap is at Dapr component resource level in Kubernetes, not app code or Dapr setup.

### Next Step

Verify component presence:
```bash
kubectl get components -n radiusclaim-azure
```

If empty or missing `statestore`, requires platform follow-up to:
- Audit Radius recipe output for Dapr component metadata
- Confirm Radius is emitting component resource to Kubernetes
- If not, update recipe or Radius resource to generate component object
- Verify component scopes include `expense-api` and `workflow-engine`

### Impact

**Hard blocker for:** Any workflow or expense-api operation that reads or writes state.  
**Operator signal:** Platform work, not application work. App code is ready; wiring is incomplete.

---

## 15. Component Validation Guidance

**Date:** 2026-03-25  
**Owner:** Eddie (Docs/Story)  
**Status:** IMPLEMENTED  
**Related Evidence:** Wesley's confirmation that `kubectl get components` returns no resources in both environment and workload namespaces.

### Problem

**Evidence:** Dapr sidecar logs show `"state store statestore is not configured"` but operators couldn't find guidance on:
1. **When components should exist** (after Step 8)
2. **How to verify Step 8 actually succeeded** (before proceeding to Step 9)
3. **What to do if components are missing**

This left operators unable to diagnose whether their failure was a deployment issue or configuration gap.

### Decision

**Add explicit component validation checkpoints** to both documentation files:

#### In `docs/end-to-end-setup-walkthrough.md` (Step 9)
- Add prominent warning block **before Step 9** that tells operators to verify components exist
- Command: `kubectl get components -n radiusclaim-azure`
- Expected: `statestore, pubsub, platform-secrets`
- If missing: "Do not proceed to Step 9 without these components."

#### In `docs/radius-validation-checklist.md` (Troubleshooting)
- Expand "Dapr components not registering" section to:
  1. **First Check** — Did Step 8 actually run? (verify namespace exists)
  2. **Detailed Troubleshooting** — What went wrong in recipe execution?
  3. **Solution** — Step-by-step remediation with exact commands

### Implementation

**Files Updated:**
- `docs/radius-validation-checklist.md` — Expanded component troubleshooting
- `docs/end-to-end-setup-walkthrough.md` — Added Step 9 prerequisite check

**Key Principle:** *Operator visibility into step execution*. If prerequisite step didn't run visibly (no pod logs, no Kubernetes manifests), operators can't debug downstream failure.

### What This Doesn't Solve

If `kubectl get components` still returns no resources **after** running `rad deploy infra/radius/environments/azure-radius.bicep`, then:
- Either Bicep file has bug
- Or Radius doesn't automatically create Dapr components
- Or recipe mechanism isn't wired correctly

**This is a platform question** requiring Graham (Platform) to investigate `rad deploy` output, Radius control plane logs, and recipe execution. Docs now point operators to that investigation.

---

## 16. Walkthrough Review: End-to-End Setup

**By:** Daisy (Lead)  
**Date:** 2026-03-25  
**Status:** REVIEW COMPLETE — CONDITIONAL REJECTION  
**Scope:** `docs/end-to-end-setup-walkthrough.md`, `docs/radius-validation-checklist.md`, cross-referenced against `infra/radius/app.bicep`, `infra/radius/environments/azure-radius.bicep`, `.github/workflows/deploy-azure.yml`, live deployment evidence, and earned skills.

### Verdict

**REJECT — must fix 6 critical issues before walkthrough can be considered fit-for-demo.**

Walkthrough is well-structured and covers operator journey from resource group to browser. Namespace-variable hygiene (`WORKLOAD_NAMESPACE` pattern) is correctly applied. However, critical gaps in deployment flow — most notably complete absence of Dapr Component backfill step — mean user following guide end-to-end will reach Step 12 with broken app.

### Critical Issues

#### C1: Missing Dapr Component backfill step in deployment flow
**Location:** Between Steps 9 and 10; also missing from GitHub Actions workflow  
**Problem:** `scripts/deploy-dapr-components.sh` exists specifically to bridge gap where Radius recipes provision Azure backing resources but do NOT project Dapr `Component` CRDs into Kubernetes. Script referenced nowhere — not in walkthrough, not in validation checklist, not in workflow. Live evidence confirms this is active blocker: Dapr sidecars report `"state store statestore is not configured"` because zero `components.dapr.io` objects exist in workload namespace.  
**Fix:** Add Step 9a after app deployment: run `./scripts/deploy-dapr-components.sh --resource-group "$AZURE_RESOURCE_GROUP"` targeting workload namespace. Add same step to GitHub Actions workflow after `rad deploy app.bicep` and before validation step. Document as known Radius behavior.

#### C2: Step 8 "What this does" misattributes resource creation
**Location:** Walkthrough lines 528–536  
**Problem:** Claims environment deployment creates "Dapr component definitions" and "Azure backing services via Radius recipes." Neither is true. Environment deployment only registers recipe templates. Azure backing resources and Dapr components triggered by `Applications.Dapr/*` in `app.bicep` during Step 9.  
**Fix:** Rewrite "What this does" block: "Registers Radius environment, configures Azure provider scope, registers three OCI-published recipe templates, creates environment namespace. Actual Azure backing resources and Dapr components created when application model deployed in Step 9."

#### C3: Step 9 prerequisite checks components in wrong namespace
**Location:** Walkthrough lines 657–661  
**Problem:** Directs users to `kubectl get components -n radiusclaim-azure`. This is environment namespace. Dapr Component CRDs must exist in workload namespace (`radiusclaim-azure-radiusclaim`) where sidecars run. Even if components projected, checking wrong namespace gives false negative/positive.  
**Fix:** Change namespace to workload namespace. Move component check to Step 9a or start of Step 10 (after app deployment, since `Applications.Dapr/*` resources trigger recipe execution).

#### C4: Validation checklist uses wrong namespace for pods throughout
**Location:** `docs/radius-validation-checklist.md` lines 336, 351–358, 366–372, 410, 432, 437, 627–630  
**Problem:** Every `kubectl get pods`, `kubectl logs`, `kubectl port-forward`, and `kubectl describe component` uses `-n radiusclaim-azure` (environment namespace). Live evidence confirms pods run in `radiusclaim-azure-radiusclaim` (workload namespace). Operators following checklist see "No resources found" for every pod command.  
**Fix:** Update all pod/log/port-forward commands to use workload namespace. Adopt `WORKLOAD_NAMESPACE` variable pattern walkthrough already uses. Keep environment namespace only for commands targeting environment.

#### C5: Validation checklist imagePullSecret patches `default` service account
**Location:** `docs/radius-validation-checklist.md` lines 563–566  
**Problem:** Patches `serviceaccount default` in environment namespace. Walkthrough correctly documents pods use NAMED service accounts (`expense-api`, `workflow-engine`, `notification-svc`) and patches each in WORKLOAD namespace. Checklist contradicts and has no effect.  
**Fix:** Align with walkthrough's correct pattern: patch named service accounts in workload namespace.

#### C6: No documentation of known Radius Component projection gap
**Location:** Walkthrough troubleshooting section and validation checklist "Dapr components not registering" section  
**Problem:** `radius-live-dapr-component-backfill` skill documents known pattern where Radius claims `Applications.Dapr/*` resources `Succeeded` but Kubernetes has zero corresponding `components.dapr.io` objects. Troubleshooting sections assume problem is always failed recipe or missing credential, not projection gap.  
**Fix:** Add troubleshooting entry distinguishing "recipe failed" from "recipe succeeded but component not projected." Reference `scripts/deploy-dapr-components.sh` as recovery path. Include sidecar-log diagnostic: if sidecar only loads `kubernetes (secretstores.kubernetes/v1)` and never loads `statestore`/`pubsub`, issue is missing projection.

### Minor Issues

**M1: Double-scheme URL in troubleshooting** — `curl "http://$EXPENSE_API_URL/healthz"` produces `http://http://...`  
**M2: Group name mismatch** — Walkthrough uses `radiusclaim-group` vs workflow uses `radiusclaim`  
**M3: `deploymentTarget='radius'` passed without explanation**  
**M4: `belgiumcentral` as example region** — less familiar, may not have all SKUs available

### What's Working Well

- **Namespace variable hygiene in walkthrough:** `RADIUS_KUBERNETES_NAMESPACE` / `WORKLOAD_NAMESPACE` separation correct
- **OCI recipe visibility guidance:** Step 6 thorough and correct
- **Named service account documentation:** Step 8b correctly identifies Radius creates named SAs
- **Troubleshooting breadth:** Namespace drift, image mismatch, port-forward fallback covered

### Recommendation

Assign 6 critical fixes to Eddie (docs) with Graham reviewing namespace and component accuracy. Validation checklist needs sweep to align with walkthrough's namespace model. `deploy-dapr-components.sh` integration is highest-priority fix — without it, no operator can complete walkthrough successfully.

**Do not merge or publish until C1–C6 resolved.**

---

## 17. bootstrap.sh Feasibility and Design

---
**Decision Date:** 2026-03-25  
**Author:** Daisy (Lead)  
**Status:** APPROVED-WITH-CONDITIONS  
**Affects:** scripts, documentation, deployment

### Verdict

**YES — a `scripts/bootstrap.sh` is the right move for this repo now.** Walkthrough has 12 manual steps, two hidden blockers (component projection gap, recipe-auth sequencing), and six critical documentation issues. Operator following walkthrough today cannot reach working app. Bootstrap script that automates happy path — with guardrails — directly addresses "can I actually use this sample?" question.

### Relationship to Walkthrough

**bootstrap.sh wraps the walkthrough; it does not replace it.**

Walkthrough teaches Radius/Dapr platform story. Script automates operator path. Both must exist:

- **Walkthrough stays as-is** (after C1–C6 fixes): explains *why* each step exists and is reference for platform teams evaluating architecture
- **bootstrap.sh is "just make it work" entry point**: runs same steps in order, with pre-flight checks and error recovery, for operators wanting working deployment without reading 40 pages first

Walkthrough should reference bootstrap.sh as fast path. bootstrap.sh should reference walkthrough as detailed explanation.

### Required Pre-Flight Checks

Script must verify all BEFORE making any changes. Fail fast, fail clearly.

#### Tool Availability (exit immediately if missing)
1. `az` CLI installed and logged in (`az account show`)
2. `kubectl` installed and cluster reachable (`kubectl cluster-info`)
3. `rad` CLI installed (`rad version`)
4. `dapr` CLI installed (for `dapr status -k` check)
5. `jq` installed
6. `docker` installed (for recipe publishing)
7. `curl` installed (for validation)

#### Cluster State (exit if prerequisites missing)
8. Kubernetes cluster reachable and user has write access
9. Dapr control plane running (`kubectl get pods -n dapr-system`)
10. Radius control plane running (`kubectl get pods -n radius-system`)

#### Azure State (exit or prompt if misconfigured)
11. Azure subscription selected (`az account show` non-empty)
12. Resource group exists OR user confirms creation
13. Radius Azure credential registered (`rad credential show azure`)

#### Recipe State (warn if stale)
14. Recipe OCI artifacts published and accessible
15. State-store recipe includes `allowSharedKeyAccess: true` (Graham's root-cause finding)

#### Existing Deployment State (prompt before overwriting)
16. If Radius environment exists: prompt to reuse or recreate
17. If Radius app exists: prompt to redeploy or skip
18. If Dapr components exist in workload namespace: prompt to overwrite or skip

### Stop-and-Ask Points

Script MUST NOT silently guess at these decision points:

1. **Resource group creation:** "Resource group 'radiusclaim-rg' does not exist. Create it in 'eastus'? [y/N]"
2. **Recipe republishing:** "Recipes may be stale. Republish to GHCR? [y/N]" (skip if `--no-publish` flag)
3. **Existing app teardown:** "Application 'radiusclaim' already exists. Redeploy in place? [y/N]"
4. **Azure credential registration:** If `rad credential show azure` fails: "Radius Azure credential not found. Register now? [y/N]"

### Idempotency Patterns

Following `radius-idempotent-deployment` skill:

- Use `rad env create <name> || true` pattern — never fail if environment exists
- Use `kubectl apply` (not `create`) for secrets and components — always safe to rerun
- Use `--dry-run=client -o yaml | kubectl apply -f -` for secret creation
- Never use `rad app delete` as routine step — destroys Azure backing resources
- Recipe publishing inherently idempotent (overwrites OCI tag)

**Risk:** `rad deploy app.bicep` triggers Azure recipe re-evaluation. If recipe parameter changes, may attempt to recreate Azure resources. Acceptable for reference sample but should be documented.

### Phase Structure

```
Phase 0: Pre-Flight Checks
  ├── Tool availability
  ├── Cluster reachability and permissions
  ├── Dapr control plane health
  ├── Radius control plane health
  ├── Azure subscription and credential state
  └── Existing deployment detection

Phase 1: Azure Foundation
  ├── Create resource group (if needed, with prompt)
  └── Verify resource group accessible

Phase 2: Radius Workspace Setup
  ├── rad workspace create kubernetes
  ├── rad group create
  ├── rad env create
  └── rad credential register azure (if needed)

Phase 3: Recipe Publishing
  ├── Verify recipe source files exist
  ├── Verify state-store recipe has allowSharedKeyAccess: true
  ├── Publish recipes to OCI registry
  └── Verify published artifacts accessible

Phase 4: Environment Deployment
  ├── rad deploy environments/azure-radius.bicep
  └── Verify environment shows correct provider scope and recipes

Phase 5: Application Deployment
  ├── rad deploy app.bicep with parameters
  ├── Wait for Radius resources to report Succeeded
  └── Verify pods running in workload namespace

Phase 6: Dapr Component Backfill
  ├── Detect workload namespace automatically
  ├── Run deploy-dapr-components.sh
  ├── Verify components.dapr.io objects exist
  └── Bounce pods to pick up new components

Phase 7: Validation (optional)
  ├── Wait for pods to stabilize after bounce
  ├── Set up port-forward or detect ingress URL
  ├── Run validate-deployment.sh
  └── Report results
```

### Key Design Decisions

1. **Reuse existing scripts:** Phases 3, 6, 7 delegate to `publish-radius-recipes.sh`, `deploy-dapr-components.sh`, `validate-deployment.sh`. bootstrap.sh is orchestrator, not reimplementation.
2. **Each phase independently safe to retry:** If Phase 5 fails, user can fix and rerun. Phases 0–4 detect existing state and skip or update in place.
3. **Explicit pod bounce after component backfill:** Existing pods won't pick up new Dapr components. Script should `kubectl rollout restart` after Phase 6.
4. **No cluster or Dapr/Radius installation:** bootstrap.sh assumes those already done. Installing AKS, Dapr, Radius is separate concern covered by walkthrough Steps 3–5.

### Risks

1. **Credential leakage in terminal history:** Script fetches storage keys and Service Bus connection strings. Never echo to stdout. Existing `deploy-dapr-components.sh` already handles correctly.
2. **Namespace drift:** Workload namespace is `{env-namespace}-{app-name}`, not environment namespace. Script must auto-detect, not assume hard-coded value.
3. **Recipe staleness:** If bootstrap.sh run without publishing recipes first, `rad deploy` pulls whatever last pushed to GHCR. Pre-flight check mitigates this.
4. **Azure Policy conflicts:** Some subscriptions enforce `allowSharedKeyAccess: false` at policy level. Script cannot fix — should detect and tell user to change policy or switch managed identity auth.
5. **Partial failure recovery:** If script fails mid-way, next run must be safe. Each phase independently idempotent.

### Implementation Guidance

**Who:** Graham (Platform Dev) should implement — it's platform orchestration, not app code or docs.  
**Support:** Eddie should update walkthrough to reference bootstrap.sh as fast path. Karen should validate full sequence on fresh cluster.

---

**Last Updated:** 2026-03-25T16:05:45Z

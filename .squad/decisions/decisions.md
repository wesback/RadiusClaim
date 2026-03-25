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

**Last Updated:** 2026-03-25T15:25:58Z

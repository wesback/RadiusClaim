# Squad Decisions

## Active Decisions


### 2026-03-25T16:29:00Z: User Directive — Azure Policy Blocks Shared Keys
**By:** Wesley Backelant (via Copilot)
**Status:** DIRECTIVE
**What:** Azure Policy blocks shared keys on this tenant (`allowSharedKeyAccess: true` denied).
**Why:** Tenant constraint that affects state-store auth, bootstrap flow, and deployment guidance.

### 2026-03-25T16:56:12Z: User Directive — Bootstrap Default Azure Location
**By:** Wesley Backelant (via Copilot)
**Status:** DIRECTIVE
**What:** The bootstrap script should default to `belgiumcentral` as the Azure location.
**Why:** User request — captured for team memory.

### 2026-03-25: Decision — State-Store Auth Pivot to Microsoft Entra
**By:** Daisy (Lead)
**Status:** BLOCKING — Phase 7
**What:** The state-store recipe, bootstrap script, and component backfill script must pivot from shared-key auth to Microsoft Entra (workload identity or service principal) auth.
**Why:** Current recipe cannot deploy on the tenant due to shared-key policy block.

**Blocked Items:**
- `infra/radius/recipes/azure/state-store.bicep` — sets `allowSharedKeyAccess: true` (ARM denied)
- `scripts/bootstrap.sh` — asserts `allowSharedKeyAccess: true` (instant failure)
- `scripts/deploy-dapr-components.sh` — generates `accountKey`-based component (unusable)

**Work Items (Graham primary):**
1. Redesign `state-store.bicep`: remove `allowSharedKeyAccess`, remove `listKeys()`, output Entra metadata, assign RBAC
2. Update `deploy-dapr-components.sh`: replace accountKey guard with Entra auth, remove key fetch
3. Update `bootstrap.sh`: replace allowSharedKeyAccess assertion with Entra-auth readiness check
4. Evaluate `pubsub.bicep`: pivot to Entra if tenant policy blocks Service Bus SAS
5. Republish OCI recipe artifacts

**Work Items (Eddie, after Graham):**
6. Update `docs/end-to-end-setup-walkthrough.md` and `docs/radius-validation-checklist.md`: remove shared-key recovery; document Entra auth only

**Work Items (Karen, after Graham + Eddie):**
7. Re-validate fresh deployment end-to-end under the shared-key-blocked policy

**Consequence:** Phase 7 end-to-end validation is blocked until Graham delivers Entra auth pivot.

### 2026-03-26: Decision — Live Statestore Failure Root Cause
**By:** Graham (Platform Dev)
**Date:** 2026-03-26
**Status:** DIAGNOSED
**What:** The latest Radius deploy failed on `Applications.Dapr/stateStores/statestore` with `RecipeDeploymentFailed`. The Blob account keeps shared keys disabled and the configured Dapr principal is missing `Storage Blob Data Contributor` on the storage account.
**Why:** Live Radius logs and cluster inspection show this is a Blob data-plane RBAC gap, not a component projection bug. Grant the Blob role to the configured principal, then rerun the Dapr component backfill so statestore can project successfully.

### 2026-03-26: Decision — GHCR Recipe Publish Auth and Validation (consolidated)
**By:** Graham (Platform Dev), Karen (Tester)
**Date:** 2026-03-26
**Status:** IMPLEMENTED — VALIDATED
**What:** `scripts/publish-radius-recipes.sh` now supports explicit GHCR credentials via `GHCR_TOKEN` and `GHCR_USERNAME`, while still allowing an existing Docker credential store. The GitHub Actions publish step passes the same credentials explicitly, and validation confirmed the workflow path is correct.
**Why:** Recipe publishing previously depended on ambient Docker auth and could fail with GHCR 403s without clear guidance. Explicit credentials make manual and CI publishing predictable, and the validation confirms the fix is safe to merge.

### 2026-03-25: Decision — Operator Docs Updated for Component Projection Gap
**By:** Eddie (Docs/Story)
**Status:** IMPLEMENTED
**What:** Component projection gap now documented in all operator paths; namespace commands fixed; two-path structure framed; pull-secret patching fixed; README references updated.
**Why:** Previous docs led operators to check wrong namespace, skip backfill, patch wrong service accounts.

**Key Changes:**
- Component projection gap → Step 9a (walkthrough) and Step 5a (checklist)
- All `kubectl` commands use `$WORKLOAD_NAMESPACE` (`radiusclaim-azure-radiusclaim`)
- Pull-secret patch targets named service accounts (`expense-api`, `workflow-engine`, `notification-svc`), not `default`
- Manual walkthrough vs. bootstrap script paths framed upfront
- `scripts/README.md` added for `deploy-dapr-components.sh` documentation

### 2026-03-25: Decision — Bootstrap Script Orchestrates Manual Deployment Path
**By:** Graham (Platform Dev)
**Status:** IMPLEMENTED
**What:** Implement `scripts/bootstrap.sh` as the operator fast path for the repo's manual Kubernetes + Radius + Azure deployment story.
**Why:** Deployable path spans multiple concerns; bootstrap makes it repeatable without replacing walkthrough docs.

**Implementation:**
1. Strong pre-flight checks: CLIs, Azure context, K8s reachability, Dapr/Radius health, workspace/group selection, resource state
2. Reuses existing scripts: `publish-radius-recipes.sh`, `deploy-dapr-components.sh`, `validate-deployment.sh`
3. Idempotent-safe behavior with stable Radius names and in-place updates
4. Interactive confirmation (default) or `--yes` for non-interactive mode
5. Dapr component backfill as first-class recovery step: backfill, restart deployments, verify sidecars
6. Falls back to `kubectl port-forward` for validation if Radius public gateway not ready

### 2026-03-25: Decision — daprd CrashLoop is Dapr Component Auth Failure
**By:** Graham (Platform Dev)
**Status:** DIAGNOSED
**What:** Current `daprd` `CrashLoopBackOff` is a Dapr component auth/config failure, not app annotation or app env wiring.
**Evidence:**
- `kubectl logs <expense-api-pod> -c daprd --previous`: `Failed to init component statestore`, `KeyBasedAuthenticationNotPermitted`
- Live `statestore` component uses `accountKey` auth
- Live storage account has `allowSharedKeyAccess: false`
- Deployment annotations/env are correct

**Operator Rule:**
1. Do not apply `accountKey`-based Blob statestore unless `allowSharedKeyAccess=true`
2. Keep Service Bus pub/sub on exactly one auth path
3. If shared-key auth disallowed, switch to Microsoft Entra auth

### 2026-03-25: Decision — Entra State-Store Redesign Implementation Plan
**By:** Graham (Platform Dev)
**Status:** PLANNED
**What:** Use the same Microsoft Entra principal already registered with Radius for Azure recipe provisioning as the Dapr Blob statestore runtime identity.
**Why:** Tenant policy blocks shared keys; reuse of existing principal keeps platform story small.

**Implementation Shape:**
1. `state-store.bicep`: remove `allowSharedKeyAccess`, output Entra metadata, assign RBAC
2. `azure-radius.bicep`: accept optional Dapr Entra identity parameters, forward into state-store recipe
3. `bootstrap.sh`: resolve Entra principal object ID upfront, pass identity parameters during environment deployment
4. `deploy-dapr-components.sh`: backfill `statestore` with Entra metadata, grant Blob RBAC if missing

### 2026-03-25: Decision — Bootstrap Radius Health Checks Target controller-manager
**By:** Graham (Platform Dev)
**Status:** IMPLEMENTED
**What:** Use `app.kubernetes.io/name=radius-controller-manager` as the Radius preflight selector in `scripts/bootstrap.sh`.
**Why:** Stock `rad install kubernetes` flow; operator docs already treat `radius-controller-manager` as authoritative Runtime signal.
**Consequence:** Bootstrap now checks same pod operators inspect manually; should align `docs/radius-validation-checklist.md` to same selector.

### 2026-03-25: Decision — Prepare-Cluster RG Verification Deduplicated
**By:** Graham (Platform Dev)
**Status:** CLOSED
**What:** Remove the duplicate `--resource-group` check from the AKS-specific bootstrap path in `scripts/prepare-cluster.sh`.
**Why:** The top-level flow already handles group verification, reuse, and creation. Removing the second check eliminates redundant "already exists" log messages while keeping `--resource-group` required and validation behavior intact.
**Validation:** Behavior tested; direct invocation and help path both work; no change to group availability guarantees.

### 2026-03-25: Decision — Bootstrap Default Azure Location Set to belgiumcentral
**By:** Graham (Platform Dev)
**Status:** CLOSED
**What:** Change `scripts/bootstrap.sh` to default `--location` to `belgiumcentral` instead of `eastus`.
**Why:** The operator-facing walkthrough already standardizes on Belgium Central; the "easy path" default should agree with the taught path.
**Affected Files:** `scripts/bootstrap.sh`, `docs/radius-validation-checklist.md` (both updated).
**Consequence:** Bootstrap now matches operator guidance without broader walkthrough rewrites.

### 2026-03-25: Decision — Cluster Prep Separated from App Deployment
**By:** Graham (Platform Dev)
**Status:** CLOSED
**What:** Treat Kubernetes cluster preparation as a separate operator phase (via `scripts/prepare-cluster.sh`) from repeatable app deployment (via `scripts/bootstrap.sh`).
**Why:** Cluster lifecycle and app deployment have different cadence. Separation makes platform story clearer and prevents silent AKS creation during repeatable deploy.
**Operator Rule:**
- Run `prepare-cluster.sh` once per cluster (or when re-validating cluster-level prerequisites)
- Run `bootstrap.sh` for each deploy/redeploy once cluster is ready
- No silent cluster creation/replacement during repeatable deployment without explicit operator opt-in
**Consequence:** Clear separation of phases; operator controls cluster decisions explicitly.

### 2026-03-25: Decision — Prepare-Cluster Control-Plane Gates Stay Explicit
**By:** Graham (Platform Dev)
**Status:** PROPOSED
**What:** Keep `scripts/prepare-cluster.sh` in verify-by-default mode for Dapr and Radius, but document more explicitly that first-time prep on a fresh cluster must include `--install-dapr --install-radius`.
**Why:** The explicit gates are deliberate safety rails for cluster-level mutations, but the operator story only stays teachable if the first-time path says that plainly instead of letting the readiness stop feel accidental.

**Operator Rule:**
- Fresh cluster or newly created AKS: run `prepare-cluster.sh` with both install flags
- Reused cluster with Dapr/Radius already present: install flags may be omitted for verification-only preflight

**Affected Files:**
- `scripts/prepare-cluster.sh`
- `scripts/README.md`
- `docs/end-to-end-setup-walkthrough.md`
- `docs/radius-validation-checklist.md`

### 2026-03-25: Decision — Prepare-Cluster kubectl Context Must Stay Stdout-Clean
**By:** Graham (Platform Dev)
**Status:** PROPOSED
**What:** Split the `prepare-cluster.sh` kubectl-context step into:
1. `select_kubectl_context` for the optional `kubectl config use-context` side effect
2. `resolve_kubectl_context` for the pure "what context is active and is it reachable?" lookup

**Why:** The old shape mixed side effects and value capture inside `KUBECTL_CONTEXT="$(resolve_kubectl_context)"`. That makes the control-flow fragile because any human-facing stdout from a context-switch command can leak into the captured value or the surrounding runtime path.

**Consequence:**
- Cluster-prep logging remains operator-friendly
- The captured `KUBECTL_CONTEXT` value stays a clean context name
- Future platform helpers should keep command-substitution functions stdout-clean

### 2026-03-25T18:21:03Z: Decision — Prepare-Cluster Must Use Dapr CLI Wait Semantics
**By:** Graham (Platform Dev)
**Status:** COMPLETED
**What:** Update `scripts/prepare-cluster.sh` to install Dapr with `dapr init -k --wait` instead of `dapr init -k`.
**Why:** `dapr init -k` returns success once the install request is accepted, not when the Dapr control plane is actually healthy. The script immediately runs its readiness check after install, so the current behavior can fail on a fresh cluster even though Dapr is still converging normally.

Using the CLI's built-in wait semantics is the smallest correct repair:
1. It matches Dapr's documented contract for Kubernetes installs.
2. It avoids teaching arbitrary sleeps into platform automation.
3. It preserves the script's existing `verify_dapr_ready` check as the final guard.

**Consequence:**
- Fresh-cluster prep becomes deterministic for the Dapr install step.
- The control-plane boundary stays explicit: install when asked, then verify readiness before proceeding.

### 2026-03-26: Decision — Bootstrap Preflights Soft-Deleted Azure Secret Stores
**By:** Graham (Platform Dev)
**Status:** IMPLEMENTED
**What:** `scripts/bootstrap.sh` now resolves the deterministic Azure Key Vault name behind the `platform-secrets` store before app deployment. If that vault is soft-deleted, it restores the vault when Azure can recover it back into the current subscription, resource group, and location; otherwise, it fails early with actionable guidance instead of letting `rad deploy infra/radius/app.bicep` fail unclearly on `Applications.Dapr/secretStores`.
**Why:** The failure is a repeatable deployment concern, not an application-model design bug. Key Vault soft-delete blocks name reuse, so the scripted operator path should tell the truth before app deployment rather than surfacing an opaque Radius recipe failure later.
**Affected Files:**
- `scripts/bootstrap.sh` — Key Vault soft-delete preflight and recovery logic
- `scripts/README.md` — Behavior documentation
- `docs/end-to-end-setup-walkthrough.md` — Integration into walkthrough
- `docs/radius-validation-checklist.md` — Soft-delete validation steps

**Supporting Pattern:**
- `.squad/skills/azure-keyvault-soft-delete-preflight/SKILL.md` — Reusable detection and recovery pattern for future platforms

### 2026-03-26: Decision — Script-First Documentation Restructure
**By:** Eddie (Docs/Story)
**Date:** 2026-03-26  
**Status:** COMPLETED
**Scope:** `docs/end-to-end-setup-walkthrough.md`

**What:** Restructured the walkthrough to make scripts the primary narrative, not an optional alternative. Manual steps (1–12) moved to optional deep-dive section.

**Why:** Original structure had manual steps dominating; operators cloning the repo would see detailed `az` and `rad` commands before learning the script-based path was faster and more reliable.

**Key Changes:**
1. Opening emphasizes two-script approach
2. New "Environment Variables" section upfront (Entra auth guidance)
3. "Quick Start: Run the Two Scripts" (Steps 1–2, then subsequent deployments)
4. Manual walkthrough (all 12 steps) moved to "Deep Dive" section with "optional" disclaimer
5. CI/CD path clearly marked as alternative

**Impact:**
- Scripts presented as primary, recommended path (not optional)
- Manual steps remain discoverable for learning/customization
- Consistent with existing README and scripts/README messaging
- No breaking changes to deployment logic or scripts

### 2026-03-26: Decision — ArgoCD Fit for RadiusClaim
**By:** Daisy (Lead)
**Date:** 2026-03-26
**Status:** REJECTED
**Requested by:** Wesley Backelant

**Recommendation:** No. ArgoCD does not belong in RadiusClaim.

**Why:**
1. **No deploy gap:** Current two-phase deployment (prepare-cluster.sh + bootstrap.sh) is complete. ArgoCD would add a fourth control plane to a sample teaching Dapr + Radius.
2. **Conflicts with Radius model:** Radius generates Kubernetes resources dynamically via recipes; ArgoCD expects static manifests in Git. This creates ownership ambiguity (who manages Deployments — ArgoCD or Radius?).
3. **Dynamic component impedance mismatch:** Dapr component backfill queries Radius outputs and generates CRDs dynamically; ArgoCD can't sync components that don't exist until recipes execute.
4. **Teaching cost exceeds value:** Adding ArgoCD adds a fourth control plane, complicates the "who deploys what" story, and dilutes the focus on Dapr + Radius boundary.
5. **Audience fit:** Target audience (platform teams) will understand ArgoCD after learning Dapr + Radius; retrofitting it in the sample conflates delivery with architecture.

**What to tell teams who ask:**
> "RadiusClaim doesn't include ArgoCD because Radius already provides the declarative application model. ArgoCD is a delivery mechanism — you can layer it on top of Radius in production. This sample focuses on the Dapr + Radius boundary so you can evaluate those two together without delivery-pipeline opinions getting in the way."

### 2026-03-26: Decision — Bootstrap Principal ID Resolution Improved
**By:** Graham (Platform Dev)
**Date:** 2026-03-26T09:15:32Z  
**Status:** IMPLEMENTED

**What:** Improved `resolve_azure_principal_id()` in `scripts/bootstrap.sh` to handle multiple Azure authentication modes with actionable diagnostics when auto-resolution fails.

**Why:** Original implementation only handled service principal lookups via `az ad sp show --id "$AZURE_CLIENT_ID"`. This failed silently when operators used user identity (interactive `az login`), managed identity, or workload identity federation without traditional service principals.

**Implementation:**
1. Function improvements:
   - Kept existing happy paths
   - Added stderr diagnostics when resolution fails
   - Provided context-specific guidance for different auth modes
   - Maintained stdout cleanliness for command substitution
2. Documentation updates:
   - `scripts/README.md`: Added "About AZURE_PRINCIPAL_ID" and "Principal ID Resolution" sections
   - `docs/end-to-end-setup-walkthrough.md`: Added inline comments explaining auto-resolution and alternatives

**Supported Auth Modes:**
- ✅ Service principal (client ID + secret) — auto-resolves principal ID
- ✅ Workload identity (federated credential without secret) — auto-resolves principal ID
- ✅ User identity (interactive `az login`) — requires manual `AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)`
- ✅ Managed identity — requires manual `AZURE_PRINCIPAL_ID=<managed-identity-object-id>`

**Operator Rule:** When auto-resolution fails, stderr diagnostics explain exactly what to do next.

**Validation:**
- ✅ Syntax validated with `bash -n`
- ✅ Function preserves stdout cleanliness
- ✅ Diagnostics go to stderr only
- ✅ Existing happy paths unchanged

### 2026-03-26: Decision — Radius existing-install readiness must honor current controller naming
**By:** Graham (Platform Dev)
**Date:** 2026-03-26
**Status:** PROPOSED

**What:** `scripts/prepare-cluster.sh` and `scripts/bootstrap.sh` should treat the stock Radius controller as `deployment/controller` with pod label `app.kubernetes.io/name=controller`, while still tolerating legacy `radius-controller-manager` naming for older clusters.

**Why:** Current Radius install docs and Helm chart use `controller`; the repo had drifted to `radius-controller-manager`, making healthy existing installs look broken and causing misleading post-install failures.

**Operator Impact:** If `rad install kubernetes` reports an existing installation and the control plane is still not ready after checking both naming shapes, the script should say plainly it did not auto-repair and point to `kubectl get deployments,pods -n radius-system` plus the reinstall command.

### 2026-03-26: Decision — Prepare-Cluster Must Wait for Radius Controller Rollout
**By:** Graham (Platform Dev)
**Date:** 2026-03-26
**Status:** PROPOSED

**What:** Treat `rad install kubernetes` as an install submission step, not a readiness guarantee. Gate the script on:
```bash
kubectl rollout status deployment/radius-controller-manager -n radius-system --timeout=5m
```

**Why:** `rad install kubernetes` has no native `--wait` flag. The script immediately checks Radius readiness after install, so it can reject a normal fresh install while the controller is still converging.

**Consequence:** Fresh-cluster prep becomes deterministic for the Radius install step, and the readiness contract stays teachable: install when asked, wait on canonical controller rollout, then verify.

### 2026-03-26: Decision — Dapr Component Projection Gap Root Cause
**By:** Graham (Platform Dev)  
**Date:** 2026-03-26  
**Status:** DIAGNOSED

**What:** Radius successfully deployed containers with Dapr sidecars and provisioned Azure backing resources via recipes, but the Dapr Component CRDs were never created in the Kubernetes namespace.

**Why:** After successful Radius deployment, cluster inspection showed:
- ✅ Sidecars present (2/2 containers on all pods)
- ✅ Dapr control plane healthy
- ✅ Annotations correct
- ✅ Azure resources provisioned (Storage, Service Bus, Key Vault)
- ❌ Component CRDs missing (`kubectl get components -n azure-radiusclaim` returns empty)

**Consequence:** Sidecars running but unconfigured; no component metadata, no auth credentials. App non-functional until `scripts/deploy-dapr-components.sh` backfills components.

**Solution:** Run `deploy-dapr-components.sh` to:
1. Query Radius recipe outputs
2. Create Kubernetes secrets with auth metadata
3. Generate Dapr Component CRDs
4. Apply to namespace
5. Restart deployments

**Auth Requirement:** Service principal (via `AZURE_CLIENT_ID` + `AZURE_CLIENT_SECRET`) or workload identity federation.

### 2026-03-26: Decision — Dapr Component Backfill Blocker (SP Auth)
**By:** Graham (Platform Dev)  
**Date:** 2026-03-26  
**Status:** BLOCKED — Requires AZURE_CLIENT_SECRET

**What:** Attempted to run `deploy-dapr-components.sh` with service principal credentials but encountered missing client secret.

**Details:**
- Service principal available: `890caf69-5a38-4bf9-950d-0430352e7396`
- Script ran successfully; created all 3 Component CRDs
- Components configured for workload identity mode (detected missing secret)
- Pods failed: `failed to get JWT SVID: no JWT SVID available`
- Workload identity federation not configured; cluster not ready

**Blocker:** `AZURE_CLIENT_SECRET` not available in environment. Secret must be retrieved from secure storage and explicitly exported.

**Rollback:** Cleanly deleted components; pods returned to stable 2/2 Running state.

**Path Forward:** Either provide client secret (2-minute fix) or implement workload identity federation (longer setup).

### 2026-03-26: Decision — Azure Workload Identity for Dapr Components (Long-Term)
**By:** Graham (Platform Dev)  
**Date:** 2026-03-26  
**Status:** IMPLEMENTED

**What:** Replaced service-principal-with-client-secret auth in Dapr component deployment with Azure Workload Identity — a clean, long-term solution that requires zero secrets in the cluster.

**Implementation:**
1. Enabled OIDC issuer + workload identity addon on AKS cluster
2. Created managed identity `radiusclaim-workload-identity` (Client ID: 061dd532-71c6-40ac-9a90-750a1a868001)
3. Created 3 federated credentials (one per service account: expense-api, workflow-engine, notification-svc)
4. Granted RBAC roles:
   - Storage Blob Data Contributor (on statestore storage account)
   - Key Vault Secrets User (on platform-secrets Key Vault)
5. Configured Dapr components with `azureClientId` only (no `azureClientSecret`)
6. Updated deployments + service accounts with workload identity labels/annotations
7. AKS webhook automatically injects federated token volume; Dapr sidecar exchanges token for Azure AD access token

**Technical Flow:**
```
Kubernetes SA Token → Azure AD Token Exchange (via federated credential) → Azure Resource Access (via RBAC)
```

**Benefits:**
- ✅ Zero secrets in cluster
- ✅ No credential rotation required
- ✅ Pod-level identity (least privilege)
- ✅ Audit trail (Azure AD logs all token exchanges)
- ✅ Simplifies developer onboarding (no env vars required)
- ✅ Aligns with "no shared keys" tenant policy

**Verification:**
```
All pods 2/2 Running
All components loaded:
  - platform-secrets (secretstores.azure.keyvault/v1)
  - statestore (state.azure.blobstorage/v2)
  - pubsub (pubsub.azure.servicebus.topics/v1)
```

**New Artifacts:**
- `scripts/deploy-dapr-components-workload-identity.sh` — Automated setup with SP fallback
- `WORKLOAD_IDENTITY_SUMMARY.md` — Technical reference
- `IMPLEMENTATION_REPORT.md` — Impact analysis

**Trade-offs:**
- Cluster dependency: AKS-specific (not portable to Kind/minikube)
- Setup overhead: Cluster update ~5-7 minutes
- Fallback available: SP mode still supported

**Future Work:**
- Migrate Service Bus pub/sub from SAS to workload identity
- Integrate setup into `bootstrap.sh`
- Update walkthrough docs

### 2026-03-26: Decision — Bootstrap Fixes Portability Audit (No Regressions)
**By:** Daisy (Researcher)  
**Date:** 2026-03-26  
**Status:** COMPLETE

**What:** Audit of 6 bootstrap fixes applied in live debugging session to verify Dapr/Radius portability impact.

**Scope:** 6 fixes examined:
1. SP credential handling (auto-detect + re-registration)
2. Bootstrap preflight checks
3. RBAC role scope
4. Radius API version (`Applications.*@2023-10-01-preview`)
5. Pull secret timing
6. Container registry (GHCR → ACR switch)

**Findings:**
- ✅ 3 items are **Clean** (no portability concerns)
- ⚠️ 3 items are **Minor** (pre-existing gaps, not regressions)
- ✅ **No cloud lock-in** introduced into application model

**Clean Items:**
1. Dapr component abstraction (resource-based)
2. App/environment decoupling (Radius pattern)
3. Radius API version (current canonical)
4. SP credential auto-detect (well-scoped)
5. SP secret re-registration (safe, idempotent)
6. Registry parameterization (GHCR default, ACR via override)

**Minor Concerns (Pre-Existing, Not Regressions):**
1. **GHCR pull secret dead code for ACR path** — Make conditional on registry type
   - If `CONTAINER_REGISTRY` starts with `ghcr.io`: create secret + pass ref
   - If ACR or native auth: skip secret + pass empty ref
   - Rename from `ghcrImagePullRef` to `imagePullSecretRef`

2. **SPN Contributor role scoped to subscription** — Narrow to resource group
   - Change `prepare-cluster.sh` scope from `/subscriptions/$ID` to `/subscriptions/$ID/resourceGroups/$RG`
   - Requires RG to exist first (already ensured)

3. **Local dev recipes missing** — Create `infra/radius/recipes/local/`
   - Would complete "swap recipes" portability promise
   - Would enable true local dev without Azure dependencies
   - Not a regression; new work item

**Bottom Line:**
- App code remains cloud-agnostic
- Dapr/Radius abstraction is structurally sound
- Scripts appropriately Azure-specific for Azure deployment path
- No portability regressions from the 6 fixes

**Highest-Priority Fix:** Make pull secret conditional on registry type (resolves confusing noise for ACR users).

**Highest-Value New Work:** Create local dev recipes (would complete architecture docs promise).



## Decision 17 — Scripts fully remediated (Pete audit)

All 8 findings from Pete's infrastructure scripts audit applied: WI Dapr path wired in bootstrap, managed identity lifecycle managed in teardown, GHCR derivation made forkable, deploy-dapr-components.sh marked deprecated, DRY_RUN standardised, platform-common.sh sourced consistently. 

**Details:**
- Fix 1: bootstrap calls deploy-dapr-components-workload-identity.sh with --cluster-name flag
- Fix 2: teardown deletes managed identity with --include-managed-identity flag (auto with --include-resource-group)
- Fix 3: teardown --workspace-name primary, --workspace deprecated, --group-name added
- Fix 4: deploy-dapr-components.sh marked DEPRECATED in header and README
- Fix 5: teardown derives GHCR owner/repo from git remote (forkable), with --ghcr-owner/--ghcr-repo overrides
- Fix 6: both deploy-dapr scripts source lib/platform-common.sh for consistent logging
- Fix 7: publish-radius-recipes.sh GHCR auth detection uses docker-credential-<store> list | grep ghcr.io
- Fix 8: bootstrap standardised all DRY_RUN checks to [ "$DRY_RUN" = true ]

**Commit:** 0fe8322

**Date:** 2026-06-05

**Status:** ✅ All scripts pass `bash -n` syntax check. Bootstrap automation ready.

## Decision 18 — GHCR Package API URL Encoding (Pete)

**Date:** 2026-06-05  
**Author:** Pete (Infrastructure Automation Specialist)  
**Status:** Implemented  

### Context

The `scripts/teardown.sh` script includes a `delete_ghcr_packages()` function to clean up container images from GitHub Container Registry (GHCR) during teardown. This function was consistently failing with 404 errors for all packages.

### Problem

Package deletion was attempting to call:
```bash
gh api -X DELETE "/user/packages/container/radiusclaim/expense-api"
```

The GitHub API was interpreting this as:
- Package owner: (authenticated user)
- Package name: `radiusclaim`
- Invalid path segment: `expense-api`

This resulted in 404 errors because there is no package named simply "radiusclaim".

### Root Cause

GitHub Container Registry uses the full image path as the package name. For images pushed as:
```
ghcr.io/wesback/radiusclaim/expense-api:latest
```

The package name in the API is `radiusclaim/expense-api` (including the forward slash).

However, forward slashes in URL paths have special meaning and must be URL-encoded when they are part of a single path parameter. The script was only encoding spaces (`%20`) but not forward slashes.

### Decision

**All forward slashes in GHCR package names MUST be URL-encoded as `%2F` when used in GitHub API paths.**

### Implementation

Changed the encoding in `scripts/teardown.sh` line 493:

**Before:**
```bash
gh api -X DELETE "/user/packages/container/${full_name// /%20}"
```

**After:**
```bash
local encoded_name="${full_name//\//%2F}"
gh api -X DELETE "/user/packages/container/${encoded_name}"
```

This properly encodes package names like:
- `radiusclaim/expense-api` → `radiusclaim%2Fexpense-api`
- `radiusclaim/recipes/state-store` → `radiusclaim%2Frecipes%2Fstate-store`

### Package Naming Convention

**Standard GHCR package structure:**
```
ghcr.io/<owner>/<package-name>:<tag>
```

Where `<package-name>` can contain slashes and becomes the package identifier in the API.

**API endpoint format:**
```
/user/packages/container/<url-encoded-package-name>
```

**Example packages in RadiusClaim:**
- `radiusclaim/expense-api`
- `radiusclaim/workflow-engine`
- `radiusclaim/notification-svc`
- `radiusclaim/recipes/state-store`
- `radiusclaim/recipes/pubsub`
- `radiusclaim/recipes/secrets`

### Consequences

**Positive:**
- GHCR package deletion will now work correctly
- Script properly handles multi-level package names (e.g., `recipes/state-store`)
- 404 errors for non-existent packages are still handled gracefully (soft warning, as intended)

**Neutral:**
- The fix is transparent to script users — no flag or behavior changes required
- Syntax verified with `bash -n scripts/teardown.sh`

**Risk:**
- None. This is a bug fix that aligns with GitHub API requirements.

### References

- GitHub REST API: [Packages - Delete a package for the authenticated user](https://docs.github.com/en/rest/packages/packages#delete-a-package-for-the-authenticated-user)
- URL encoding spec: RFC 3986 (forward slash = `%2F`)
- Related file: `scripts/teardown.sh` line 481-498

# Project Context & Leadership Summary

- **Owner:** Wesley Backelant
- **Project:** RadiusClaim — Dapr + Radius reference sample (formerly CloudExpense Lite)
- **Stack:** .NET 10 minimal APIs, Dapr .NET SDK, Dapr Workflows, Radius, Azure Container Apps, Azure-backed Dapr components
- **Created:** 2026-03-23

## Core Context

**Leadership:** Daisy led sample from design through Phase 7 completion (2026-03-23 to 2026-03-24). Established governance: sample stays intentionally small, reference-quality, portable. Dapr handles app patterns; Radius handles platform wiring; Azure is example target only.

**Architecture:** Three-service boundary (expense-api, workflow-engine, notification-svc) with five Dapr building blocks (State, Workflows, Pub/Sub, Service Invocation, Secrets). Shared expense contract model with traceability (ExpenseId + CorrelationId). Auto-approve threshold at $100.

**Key Decisions:**
1. **Phase 1–4:** App track complete. Dapr contracts stable. Three services wired for state, workflow, pub/sub.
2. **Phase 5–6:** Platform track complete. Local dev with Redis (Dapr overlays). Azure deployment with recipes.
3. **Phase 7 Radius redesign:** Radius is primary orchestrator. Azure bootstrap minimal (substrate only). `rad deploy` exercises app + component wiring. ACA fallback documented but not primary path.
4. **2026-03-24 Critical findings:** Full codebase review found 7 critical infrastructure issues. Radius.Compute namespace must revert to Applications.Core (stock Radius 0.55 incompatibility). Recipe type mismatches (pub/sub, state store) require fix. CI/CD missing auth step.

**Current Status:** All phases complete. Live deployment revealed Radius.Compute blocker. Graham implementing revert. Karen validating fresh deployment. Follow-ups: C2 pub/sub type, C3 state version, C7 CI auth.

---

## 2026-03-26: Radius Azure Provider Error RCA

**Context:** Persistent "Invalid deployment template" error on `rad deploy infra/radius/environments/azure-radius.bicep` across multiple sessions despite credential registration attempts.

**Investigation:**

1. **Bicep Analysis:**
   - `azure-radius.bicep` defines `Radius.Core/environments@2024-01-01` resource
   - Contains `providers.azure.scope` metadata pointing to subscription/resource group
   - Defines THREE Azure-backed recipes: state-store, pubsub, secrets (all point to OCI registry)
   - Does NOT directly provision Azure resources, only declares recipe metadata

2. **Bootstrap Script Sequence (lines 800-877):**
   ```
   Line 800-818: First credential registration attempt (SHOULD_REGISTER_AZURE_CREDENTIAL)
   Line 832-851: Second credential registration attempt (duplicate, checks if already exists)
   Line 853-868: rad deploy azure-radius.bicep with all parameters
   Line 874-876: rad env update --azure-subscription-id --azure-resource-group
   ```

3. **Official Radius Documentation:**
   - Azure provider setup guide: https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-sp/
   - Manual configuration sequence: `rad env update` FIRST, THEN `rad credential register`
   - Quote: "Use rad env update to update your Radius Environment with your Azure subscription ID and Azure resource group"
   - Then: "Use rad credential register azure to add the Azure service principal"

4. **Known Issue Research:**
   - GitHub issue #11462: Radius gives misleading "Azure provider not configured" error when the real problem is API version or resource type issues
   - Error message doesn't reflect actual cause — can be triggered by wrong API version, not just missing credentials

**Root Cause:**

The sequence is WRONG. Current bootstrap does:
1. `rad credential register` (lines 832-851)
2. `rad deploy azure-radius.bicep` (line 868)
3. `rad env update` (lines 874-876)

But Radius requires:
1. `rad env update` to tell Radius WHERE to deploy Azure resources
2. `rad credential register` to tell Radius HOW to authenticate
3. THEN environment bicep can be deployed

The environment bicep contains `providers.azure.scope` which is DESCRIPTIVE metadata, but `rad env update` is what Radius actually reads for Azure provider configuration. Without `rad env update` being called BEFORE deployment, Radius doesn't know the Azure target scope and fails with "Azure provider not configured".

**Evidence:**
- Line 873 comment says: "The bicep's azureProviderScope is descriptive metadata; this CLI call is what Radius reads."
- This comment is AFTER the deploy, meaning the script acknowledges env update is required but does it too late
- Official docs show env update must come before credential registration

**Why Previous Fixes Failed:**
- Adding `rad credential register` in `prepare-cluster.sh` (Fix #1): Wrong — credentials registered too early, no environment exists yet
- Adding `rad env update` AFTER bicep deploy in `bootstrap.sh` (Fix #2): Wrong — too late, deploy already tried and failed
- Adding second `rad credential register` BEFORE bicep deploy (Fix #3): Still wrong — env update is the missing piece, not more credential calls

**Fix Required:**
Move `rad env update` (lines 874-876) to BEFORE `rad deploy azure-radius.bicep` (line 868).

---

## Session: Bootstrap Live Debug (2026-03-26)

### What happened
Ran `./scripts/bootstrap.sh --resource-group radiusclaim-rg --yes` iteratively. Found and fixed 6 issues until full deployment succeeded.

### Fixes applied
1. **Auto-fill Azure identity** — bootstrap.sh now auto-detects ClientID/TenantID from `rad credential show azure` when env vars aren't set
2. **Stale SP secret** — always re-register credential when `AZURE_CLIENT_SECRET` is available
3. **Missing Contributor role** — `ensure_radius_recipe_rbac()` now grants both Contributor AND User Access Administrator
4. **Wrong bicep types** — reverted all `Radius.*@2024-01-01` back to `Applications.*@2023-10-01-preview` (Radius 0.55.0 doesn't support `Radius.Dapr/*`)
5. **Pull secret timing** — moved GHCR pull secret creation before `rad deploy app.bicep`
6. **Registry switch** — created ACR (`radiusclaimacr`), attached to AKS, rebuilt images as `linux/amd64`

### Key learnings
- `rad credential show azure -o json` outputs preamble to stdout — must filter with `sed -n '/^{/,$p'`
- BCP081 warning on `Radius.*` types is NOT harmless — it means the type doesn't exist in the installed Radius version
- Radius `runtimes.kubernetes.pod.spec.imagePullSecrets` does NOT work in `2023-10-01-preview` — use SA-level imagePullSecrets or ACR attach instead
- Always build with `--platform linux/amd64` for AKS on ARM Macs
- ACR + `az aks update --attach-acr` eliminates pull secret complexity entirely

### Final state
- All 3 services running (2/2 ready with Dapr sidecars)
- Gateway endpoint: `http://expense.radiusclaim.9.160.144.105.nip.io` → HTTP 200
- Decision document: `.squad/decisions/inbox/daisy-bootstrap-live-debug.md`

## Bootstrap Success & Gateway Live (2026-03-26 Post-Debug)

### Status Update
✅ Deployment **fully succeeded** on 8th attempt after all 6 fixes implemented.

### Gateway Verification
- **URL:** http://expense.radiusclaim.9.160.144.105.nip.io
- **Status:** HTTP 200 OK
- **Services:** All 3 running with 2/2 Dapr sidecars ready
- **Container Registry:** ACR (radiusclaimacr.azurecr.io) with amd64 images

### Critical Decision: Applications.* Types
**DO NOT migrate bicep types to Radius.*** until Radius version supports `Radius.Dapr/*` resources.

**Reason:** Radius 0.55.0 incompatibility
- `Radius.Dapr/*` does NOT exist at any version
- `Radius.Core/*` only available at @2025-08-01-preview (not in 0.55.0)
- `Applications.*@2023-10-01-preview` are the correct types for current Radius version
- BCP081 warnings are **real errors** in this context (not just cosmetic)

**Action:** All bicep files reverted to Applications.* types and validated.

### ACR Decision
Recommend using radiusclaimacr.azurecr.io as standard container registry going forward.
- Native AKS-ACR integration via `az aks update --attach-acr`
- Eliminates image pull secret management
- Managed identity grants AcrPull to kubelet automatically
- Always build with `--platform linux/amd64`

### Orchestration Log
Generated: `.squad/orchestration-log/2026-03-26T20-22-59Z-daisy-live-bootstrap.md`

### Session Log
Generated: `.squad/log/2026-03-26T20-22-59Z-bootstrap-deploy-success.md`
Contains full decision audit trail, technical findings, and deployment commands.

---

## 2026-03-27: Portability Audit — Post-Debugging Session

**Triggered by:** Wesley requested a full best-practices audit after a 3.3-hour live debugging session applied 6 fixes to get the app deploying.

**Files Audited:**
- `infra/radius/app.bicep`
- `infra/radius/environments/azure-radius.bicep`
- `infra/radius/environments/dev.bicep`
- `scripts/bootstrap.sh`
- `scripts/prepare-cluster.sh`
- `scripts/lib/platform-common.sh`
- `docs/architecture.md`
- `.github/workflows/deploy-azure.yml`

**Key Findings:**

1. **Dapr portability is architecturally sound but not realized for local dev.** All Dapr components use `resourceProvisioning: 'recipe'` with parameterized recipe names. The `daprBackings` param in `app.bicep` allows environment-level recipe swapping. However, `dev.bicep` still wires to Azure recipes — no local Redis/RabbitMQ recipes exist yet.

2. **`Applications.*@2023-10-01-preview` is still the canonical Radius API version.** No `Radius.*` namespace exists in the current release. Fix #4 is correct. No timeline risk identified.

3. **ACR switch is clean — parameterized, not hardcoded.** `app.bicep` defaults to GHCR, `bootstrap.sh` accepts `--container-registry`, and CI still uses GHCR. The ACR switch was a runtime parameter, not a codebase mutation.

4. **GHCR pull secret code is dead for ACR path.** Lines 914-933 of bootstrap.sh still create `ghcr-pull-secret` and pass `ghcrImagePullRef=ghcr-pull-secret` even when using ACR with managed identity. Should be conditional.

5. **RBAC scoping is mixed.** `prepare-cluster.sh` creates the SP with subscription-scoped Contributor. `bootstrap.sh` adds UAA at resource group scope only. The subscription-scope Contributor in prepare-cluster is broader than necessary.

6. **SP credential auto-detect is sound.** The `rad credential show azure` fallback is idempotent and well-documented in stderr diagnostics. Re-registering on secret availability is a safe upsert.

**Audit report written to:** `.squad/decisions.md` (merged from inbox)

## Phase 7 (2026-03-26) — Portability Review

### Deliverable

Comprehensive audit of 6 bootstrap fixes applied in live debugging session to verify Dapr/Radius portability impact.

### Summary

- ✅ **No portability regressions** from any of the 6 fixes
- ✅ Dapr component abstraction is structurally sound (resource-based, not connection-string-based)
- ✅ App/environment decoupling preserved (Azure-specific config flows through environment files)
- ✅ App code remains cloud-agnostic
- ⚠️ 3 minor pre-existing gaps identified (not caused by fixes)

### Audit Details

**Clean Items (no concerns):**
- Dapr component abstraction via Radius resources ✅
- App/environment decoupling ✅
- Radius API version (`Applications.*@2023-10-01-preview`) ✅
- SP credential handling (auto-detect + re-registration) ✅
- Registry parameterization ✅
- Container platform constraints (`linux/amd64` optional) ✅
- UAA justification (needed for RBAC assignments) ✅

**Minor Concerns (pre-existing, not regressions):**
1. **GHCR pull secret dead code for ACR** → Make conditional on registry type
   - If `CONTAINER_REGISTRY` starts with `ghcr.io`: create secret + pass ref
   - If ACR or native auth: skip secret + pass empty ref
   - Rename to `imagePullSecretRef` for registry-neutrality

2. **SPN Contributor role scoped to subscription** → Narrow to resource group
   - Change `prepare-cluster.sh` scope from `/subscriptions/$ID` to `/subscriptions/$ID/resourceGroups/$RG`
   - Requires RG to exist first (already ensured)

3. **Local dev recipes missing** → Create `infra/radius/recipes/local/`
   - Would complete architecture docs promise ("swap Azure Blob for Redis")
   - Would enable true local dev without Azure dependencies
   - New work item, not a regression

### Highest-Priority Fix

Make pull secret conditional on registry type (resolves confusing noise for ACR users).

### Highest-Value New Work

Create local dev recipes (would complete portability story).

### Status

✅ COMPLETE — Audit report merged into `.squad/decisions.md`

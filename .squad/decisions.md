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


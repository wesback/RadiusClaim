# Pete — History

## Project Context

**Project:** RadiusClaim — .NET reference application demonstrating portable distributed systems using Dapr (app-layer building blocks) and Radius (infrastructure abstraction).

**Stack:** .NET 9, Dapr, Radius 0.55.0, AKS, Azure (Storage, Service Bus, Key Vault), Bicep, bash scripts.

**User:** Wesley Backelant

**Team root:** `/Users/wesleyb/git/RadiusClaim`

## Key Files (Pete's Domain)

- `scripts/bootstrap.sh` — main deployment orchestration (rad credential register → rad env update → rad deploy env → rad deploy app → pull secret)
- `scripts/teardown.sh` — resource cleanup (known bug: AKS skipped then deleted anyway via resource group sweep — fix in progress)
- `scripts/prepare-cluster.sh` — pre-cluster setup (AKS, kubeconfig, Radius workspace, SPN with `--create-spn` flag)
- `scripts/deploy-dapr-components.sh` — original Dapr component deployment (SP-based, deprecated)
- `scripts/deploy-dapr-components-workload-identity.sh` — workload identity version (current canonical)

## Current Cluster State (as of joining)

- **AKS:** `radiusclaim-aks` in `radiusclaim-rg`
- **Namespace:** `azure-radiusclaim`
- **Managed identity:** `radiusclaim-workload-identity` (client ID: `061dd532-71c6-40ac-9a90-750a1a868001`)
- **OIDC + Workload Identity:** enabled on AKS
- **Federated credentials:** expense-api, workflow-engine, notification-svc
- **Dapr components:** statestore (Blob, WI), pubsub (Service Bus, WI in progress), platform-secrets (Key Vault, WI)
- **Gateway:** `http://expense.radiusclaim.9.160.144.105.nip.io`

## Known Issues on Hire

- `teardown.sh` bug: `--aks-cluster` not provided → script says "skipping AKS" but deletes it anyway via resource group sweep. Graham is fixing this (agent: graham-teardown-fix).
- pubsub Service Bus still on SAS (workload identity migration in progress via graham-servicebus-wi agent).

## Learnings

### 2026-03-27: Zero-Secret Dapr Milestone Complete (Scribe)

**Update from Scribe execution of graham-servicebus-wi spawn manifest:**

Service Bus pubsub component has been migrated from SAS connection string to Azure Workload Identity, completing the zero-secret achievement for all Dapr components. The deployment script `deploy-dapr-components-workload-identity.sh` is now the canonical version for cluster deployments and includes:

- Service Bus RBAC grant (Azure Service Bus Data Owner role)
- Workload identity component manifest generation for all 3 Dapr components
- No secret creation in workload identity mode
- Clear verification steps for operators

When the cluster is next recreated, all Dapr components will authenticate via Azure AD federated tokens — zero shared secrets in the cluster.

**Related:**
- `.squad/log/2026-03-27T08-55-00Z-servicebus-wi-complete.md` — Session completion log
- `.squad/decisions/decisions.md` — Merged: Service Bus zero-secret migration, teardown script pattern
- `.squad/orchestration-log/2026-03-27T08-55-00Z-graham-servicebus-wi.md` — Orchestration record


## Learnings

### 2026-06-05 — Full Scripts Audit

**bootstrap.sh calls the deprecated script.** Line 960 invokes `deploy-dapr-components.sh` (SP/legacy), not `deploy-dapr-components-workload-identity.sh`. The entire workload identity setup path (managed identity, federated creds, deployment label patching) is never run from bootstrap. This is the #1 integration gap.

**Managed identity orphaned by teardown.** `deploy-dapr-components-workload-identity.sh` creates `radiusclaim-workload-identity`. Teardown has no code to delete it. Resource accumulates across cycles.

**Flag naming divergence.** `--workspace-name` in bootstrap/prepare vs `--workspace` in teardown. `--group-name` exists in bootstrap/prepare but is missing from teardown entirely.

**GHCR owner/repo hardcoded in teardown.** `delete_ghcr_artifacts()` hardcodes `owner="wesback"`, `repo="radiusclaim"`. Not forkable without editing source.

**Both deploy-dapr scripts don't source lib/platform-common.sh.** They use raw echo/exit patterns — inconsistent logging, no dry-run support from the common layer.

**WI script header comment names wrong file.** Says `deploy-dapr-components.sh` not `deploy-dapr-components-workload-identity.sh`.

**README doesn't mark deploy-dapr-components.sh deprecated.** Operators won't know to use the WI version.

**DRY_RUN style inconsistency.** bootstrap.sh mixes `if "$DRY_RUN"` (command invocation) with `[ "$DRY_RUN" = true ]`. Both work; inconsistency is a maintenance hazard.

**DRY_RUN style inconsistency.** bootstrap.sh mixes `if "$DRY_RUN"` (command invocation) with `[ "$DRY_RUN" = true ]`. Both work; inconsistency is a maintenance hazard.

**publish-radius-recipes.sh auth detection unreliable.** The pre-publish GHCR credential check (`docker info | grep ghcr.io`) always fails, so the warning fires for every operator regardless of actual auth state.

---

## 2026-03-27: Full Scripts Audit → Recommended Actions (1–8)

**Critical Issues (must fix before bootstrap automation):**

1. **bootstrap.sh line 960:** Change call from `deploy-dapr-components.sh` → `deploy-dapr-components-workload-identity.sh --cluster-name $CLUSTER_NAME`
2. **teardown.sh managed identity cleanup:** Add deletion code for `radiusclaim-workload-identity` resource, gated by flag (e.g., `--aks-cluster-name`) or visible skip warning

**Secondary Issues (consistency + quality):**

3. **Flag naming:** Rename teardown `--workspace` → `--workspace-name` (keep old name as hidden alias)
4. **teardown missing flag:** Add `--group-name` parameter to match bootstrap/prepare-cluster
5. **GHCR hardcoded:** Derive owner/repo from `git remote get-url origin` in teardown's `delete_ghcr_artifacts()`, with optional flag override
6. **deploy-dapr logging:** Add `source lib/platform-common.sh` to both deploy-dapr scripts; replace all `echo "Error"` + `exit` with `fail()`, `log_info()`, `log_success()` calls
7. **WI script header:** Fix comment in `deploy-dapr-components-workload-identity.sh` to name correct filename
8. **README deprecation:** Mark `deploy-dapr-components.sh` deprecated in `scripts/README.md`; point operators to WI version

**References:**
- Audit date: 2026-03-27T09:05:00Z
- Audit requested by: Wesley Backelant
- Scribe orchestration: `.squad/orchestration-log/2026-03-27T09-05-00Z-pete-scripts-audit.md`


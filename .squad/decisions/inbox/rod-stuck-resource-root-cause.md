# Rod — Root cause analysis for stuck `platform-secrets` / `statestore` (2026-04-01)

## Bottom line

The most likely failure mode was:

1. A **first `bootstrap.sh` run** started a `rad deploy infra/radius/app.bicep`.
2. That deploy created or updated Dapr resources (`platform-secrets`, `statestore`) under an older or different Radius environment binding.
3. The deploy was **interrupted or failed mid-flight** while Radius still considered those resources to be **in progress / provisioning**.
4. Later, Wesley re-ran `bootstrap.sh` after the project had standardized on environment name **`azure`**.
5. The second run saw old Dapr resources still bound to the previous environment ID (for example `radiusclaim-azure`) and tried to delete them as stale.
6. Radius UCP accepted the delete (`202 Accepted`) but its async worker could not finish because the resource was still marked as provisioning, so it kept retrying and then gave up.
7. Result: **zombie Radius resources** — stale control-plane objects that block redeploys.

## Evidence from the repo

### 1) The app deploy owns these Dapr resources

`infra/radius/app.bicep` defines:

- `Applications.Dapr/stateStores` named `statestore`
- `Applications.Dapr/secretStores` named `platform-secrets`

Both are explicitly bound to the injected Radius **environment ID**:

- `properties.environment: environment`

So these are not independent Kubernetes-only artifacts; they are Radius tracked resources attached to a specific environment object.

### 2) The environment naming changed / can mismatch

Current defaults are:

- app: `radiusclaim`
- env: `azure`
- namespace: `radiusclaim-azure`

`scripts/bootstrap.sh` contains special cleanup for stale environments and stale app/component resources bound to a **different environment**, including comments that call out the old-name example:

- old env like `radiusclaim-azure`
- canonical env now `azure`

That is strong evidence this exact mismatch already happened in this project.

### 3) Bootstrap explicitly anticipates interrupted `rad deploy`

`bootstrap.sh` already documents this for container resources:

> When a previous `rad deploy` times out or is interrupted, Radius may leave container resources in "Updating" (or other in-progress) provisioning states.

That same failure class explains the Dapr resource symptom too: if the original deploy never completed, the tracked resource can remain in a non-terminal state.

### 4) Prior diagnosis matches this control-plane pattern

From `rod-ucp-deletion-diagnosis.md`:

- `platform-secrets` and `statestore` still existed in Radius
- both had `properties.environment` pointing to stale env `radiusclaim-azure`
- live app was bound to env `azure`
- Kubernetes had **no live Dapr component CRDs**
- UCP delete worker retried with `resource is still being provisioned`

That combination means the problem was in the **Radius control plane**, not a live Kubernetes finalizer deadlock.

## Most likely sequence Wesley went through

## Phase 1 — first run

Wesley likely ran bootstrap during the period where the app/environment topology was still changing:

- environment namespace was `radiusclaim-azure`
- environment name may also have been `radiusclaim-azure`, or Radius resources were at least created under that environment ID
- `rad deploy infra/radius/app.bicep` started creating:
  - application `radiusclaim`
  - `statestore`
  - `platform-secrets`
  - `pubsub`
  - container resources

During that run, one of these likely happened:

- he hit **Ctrl+C**
- the shell/session died
- `rad deploy` failed/timed out mid-run
- bootstrap exited after a later failure while Radius was still reconciling

There is **no SIGINT/SIGTERM trap** in `bootstrap.sh` for Radius cleanup. The only trap is:

- `trap cleanup EXIT`

and that cleanup only stops the port-forward process. It does **not** cancel or roll back any in-flight Radius deploy.

So if the script is interrupted, Radius is left to finish or fail on its own.

## Phase 2 — project naming normalized

Later, bootstrap was re-run with the now-standard defaults:

- env name = `azure`
- namespace = `radiusclaim-azure`

`bootstrap.sh` now does two kinds of stale detection:

1. stale **environment** owning the namespace
2. stale **application / Dapr resources** whose `properties.environment` does not match the current target env ID

That means the second run found Dapr resources still bound to the old environment ID and classified them as stale.

## Phase 3 — cleanup path triggered

On the re-run, bootstrap hit this logic:

- list `Applications.Dapr/secretStores`
- list `Applications.Dapr/stateStores`
- compare each resource’s `.properties.environment` to the current target env ID for `azure`
- if different, delete it

So `platform-secrets` and `statestore` were not random casualties; they were deleted specifically because bootstrap correctly detected:

**“this resource belongs to a different environment than the one I’m deploying now.”**

## Phase 4 — delete got stuck

`rad resource delete` returned success/accepted semantics (`202`), but Radius UCP then tried to process the delete asynchronously.

The delete never completed because UCP still considered the resource to be **provisioning**.

So the real trap is:

- stale environment mismatch exposed the problem
- but the underlying blocker was the resource’s prior **unfinished provisioning state**

That is why delete retried and eventually hit the max retry count.

## What actually caused the “different environment” warning?

### Most likely cause

**A naming transition from old env `radiusclaim-azure` to canonical env `azure`, combined with an incomplete earlier deploy.**

This is more likely than “Wesley intentionally passed a different `--env-name` on the second run,” because:

- the repo defaults are now `azure`
- bootstrap has explicit guards/comments referencing exactly this historical mismatch
- prior diagnosis showed stale resources bound to `radiusclaim-azure`

### Could a failed mid-run also contribute?

Yes. A failed or interrupted earlier run is probably what left the resource half-provisioned **under the old environment binding**.

### Fresh cluster after teardown?

Possible, but less likely as the primary cause here. If this had been only a fresh cluster plus leftover cloud resources, you would expect Azure-side collisions (like soft-deleted Key Vault issues). Instead, the diagnosis showed stale **Radius control-plane** resources still present and referencing the old environment.

So the strongest explanation is:

**old Radius environment identity + interrupted deploy + later re-run under new environment identity**

## Why the resource stays stuck

Because Radius tracks provisioning state separately from what the CLI shows synchronously.

The likely sequence is:

1. `rad deploy` created/updated `platform-secrets` and `statestore`
2. recipe-backed provisioning started
3. deploy was interrupted or failed before Radius marked the resources `Succeeded`
4. on re-run, delete was requested
5. UCP async delete worker refused to finalize deletion because the tracked resource still looked like it was actively provisioning

That matches the UCP error exactly:

> `resource is still being provisioned`

Important detail:

- prior notes showed **no live Kubernetes Dapr Component** for these resources
- so this was not “Kubernetes object won’t disappear”
- it was “Radius control-plane metadata is internally wedged”

In short:

**the resource was already broken before the delete. The delete just exposed it.**

## Operational guidance — how to avoid it

1. **Do not interrupt `bootstrap.sh` during `rad deploy`.**
   - Especially not during environment/app deploy sections.
   - If you must stop, expect Radius may continue reconciling in the background.

2. **Wait for `rad deploy` to settle before re-running bootstrap.**
   - Check `rad resource list` / `rad resource show` first.
   - If a resource is still `Provisioning`, `Updating`, or `Failed`, do not immediately stack another bootstrap run on top.

3. **Do not casually change the Radius environment name for the same namespace/app.**
   - In this repo the namespace stayed `radiusclaim-azure` while the canonical env became `azure`.
   - That can strand older resources under the prior environment ID.

4. **If a bootstrap run fails mid-way, inspect Radius state before retrying.**
   - Check:
     - `rad env list`
     - `rad resource list Applications.Core/applications`
     - `rad resource list Applications.Dapr/secretStores`
     - `rad resource list Applications.Dapr/stateStores`
   - Confirm resources are bound to the environment you intend to reuse.

5. **Treat “different environment” and “in progress state” as a pair.**
   - “different environment” means you found stale ownership
   - “still being provisioned” means the stale object is also internally wedged

6. **If you are renaming environments, clean old Radius resources first.**
   - Don’t rely on the next deploy to sort it all out safely if the previous deploy was interrupted.

## Should `bootstrap.sh` add a SIGINT/SIGTERM trap?

## Recommendation: **Yes — but as best-effort diagnostics/guard rails, not true rollback**

### Why yes

Right now the script only traps `EXIT` to stop port-forwarding. If the user presses Ctrl+C during `rad deploy`, bootstrap provides no warning, no post-interrupt diagnosis, and no reminder that Radius may still be reconciling resources.

A SIGINT/SIGTERM trap would help by:

- warning that Radius operations may still be in progress
- printing the exact commands to inspect stuck resources
- possibly waiting briefly and showing current provisioning states
- reducing the chance that the operator immediately re-runs bootstrap into half-finished state

### Why not as a “cleanup rollback” mechanism

A trap cannot reliably undo a partially accepted `rad deploy`.

Once Radius has accepted the deploy and started async reconciliation:

- the local shell script does not own the operation anymore
- deleting resources inside the trap may make things worse
- a forced cleanup during active reconciliation can create the same stuck-state race we just diagnosed

So the trap should be:

- **informational / defensive**
- not an automatic “delete everything on Ctrl+C” rollback

### Best recommendation

Add a SIGINT/SIGTERM trap that:

1. warns the user that Radius deploy may still be running asynchronously
2. prints inspection commands
3. exits non-zero

But **do not** automatically issue `rad resource delete` from that trap unless the script has a safe, operation-aware cancellation model.

## Final conclusion

Wesley most likely did **not** directly “break deletion.”

What he most likely did was:

- start bootstrap under the old environment identity,
- interrupt or lose the deploy before Radius finished provisioning,
- later re-run bootstrap under the new canonical environment (`azure`),
- which triggered stale-resource cleanup,
- and Radius then could not delete those stale Dapr resources because they were already stuck in an unfinished provisioning state.

So the real root cause is:

**an interrupted/failed earlier deploy combined with an environment identity mismatch across re-runs.**

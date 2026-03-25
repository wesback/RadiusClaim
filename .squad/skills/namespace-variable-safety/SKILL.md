# Skill: Namespace Variable Safety in Infrastructure Docs

**Domain:** Documentation patterns for Kubernetes + Radius deployments  
**Owner:** Eddie (Docs/Story)  
**Status:** Proven & Reusable

---

## Problem Statement

In multi-namespace Kubernetes deployments orchestrated by Radius, operators must work with **conceptually different namespaces** that serve different roles:

1. **Environment namespace** — where Radius infrastructure, Dapr components, and backing service specs live
2. **Workload namespace** — where application pods actually run

When docs reuse the **same shell variable** for both namespaces, operators copying code blocks can accidentally reassign the variable, causing Radius to misinterpret the workload namespace as the environment namespace.

**Real failure:** Deployment attempted to double the namespace: `radiusclaim-azure-radiusclaim` → `radiusclaim-azure-radiusclaim-radiusclaim`.

---

## Pattern: Explicit Variable Separation

**Rule 1: One variable per namespace role**
```bash
# Never reassign the environment namespace variable
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure"

# Use a distinct variable for workload operations
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"
```

**Rule 2: Use variable names that reflect role, not just "namespace"**
- ❌ Bad: `export NS="radiusclaim-azure-radiusclaim"` — too generic, easy to confuse
- ❌ Bad: `export NAMESPACE="..."` — reuses across contexts
- ✅ Good: `export ENVIRONMENT_NAMESPACE="radiusclaim-azure"`
- ✅ Good: `export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"`

**Rule 3: Make the namespace role explicit in comments**
```bash
# For environment deployment (Step 7)
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure"  # ← environment namespace
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters kubernetesNamespace="$RADIUS_KUBERNETES_NAMESPACE"

# For workload inspection (Step 9+)
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"  # ← workload namespace
kubectl get pods -n "$WORKLOAD_NAMESPACE"
```

**Rule 4: Document the distinction early and reinforce in code blocks**
- Add a "Namespace Roles" section near the first environment deployment step
- Explicitly state: "Environment and workload are separate concepts with separate kubectl namespaces"
- Repeat the distinction in troubleshooting sections (where copy-paste errors are most common)

---

## Validation Checklist

Before finalizing deployment docs:

- [ ] **Variable names are distinct** — no variable is reassigned to different namespace values
- [ ] **Comments clarify role** — each export includes `# ← environment namespace` or `# ← workload namespace`
- [ ] **Early documentation** — "Understanding Namespace Roles" section exists before first kubectl workload commands
- [ ] **All rad deploy commands** use environment namespace (never reassigned)
- [ ] **All kubectl commands on workloads** (pods, logs, port-forward, etc.) use workload namespace
- [ ] **Troubleshooting sections** explicitly guide operators to use the correct variable
- [ ] **No copy-paste conflicts** — grep for reassignments confirms no variable gets overwritten across steps

### Grep Validation
```bash
# Should show ONE assignment to environment namespace
grep 'export RADIUS_KUBERNETES_NAMESPACE=' docs/*.md

# Should show ZERO kubectl commands using RADIUS_KUBERNETES_NAMESPACE
grep 'kubectl.*RADIUS_KUBERNETES_NAMESPACE' docs/*.md

# Should show multiple kubectl commands using WORKLOAD_NAMESPACE
grep 'kubectl.*WORKLOAD_NAMESPACE' docs/*.md | wc -l  # ← should be >0
```

---

## Real-World Example (RadiusClaim)

**Before (Broken):**
```bash
# Step 7
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure"
rad deploy infra/radius/environments/azure-radius.bicep ...

# Step 9 (operator copy-pastes and accidentally reassigns)
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure-radiusclaim"  # ← Wrong!
kubectl rollout status deployment/expense-api -n "$RADIUS_KUBERNETES_NAMESPACE"
# Radius now thinks the environment namespace is the workload namespace
# Result: double namespace bug
```

**After (Fixed):**
```bash
# Step 7
export RADIUS_KUBERNETES_NAMESPACE="radiusclaim-azure"  # ← environment namespace
rad deploy infra/radius/environments/azure-radius.bicep \
  --parameters kubernetesNamespace="$RADIUS_KUBERNETES_NAMESPACE"

# Step 9 (operator uses a different variable)
export WORKLOAD_NAMESPACE="radiusclaim-azure-radiusclaim"  # ← workload namespace
kubectl rollout status deployment/expense-api -n "$WORKLOAD_NAMESPACE"
# Clear intent, no accidental reassignment
```

---

## Transferability

This pattern applies to **any multi-namespace Kubernetes deployment** where:
- Different logical layers use separate Kubernetes namespaces
- Operators copy code blocks from different sections
- Variable names must prevent accidental reuse

Examples:
- Dapr sidecar injections in separate namespaces
- Multi-tenant workload isolation
- Control plane vs. application plane separation
- Any "infrastructure namespace" + "workload namespace" pattern

---

## Decision Impact

- **For Operators:** Copy-paste safety is now baked into variable naming; no risk of double-namespace bugs
- **For Docs Authors:** Explicit role-based variable names reduce cognitive load ("Which namespace goes here?")
- **For Future Work:** Any new multi-namespace deployment section should follow this pattern automatically

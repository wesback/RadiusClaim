# RadiusClaim Scaling Boundaries and Mitigation Strategies

> **📌 Note:** This document discusses scaling trade-offs in RadiusClaim's `expenseIndex` design. The state store has since migrated from Azure Blob Storage to PostgreSQL for ACID transactional support (required by Dapr Actors). Many patterns and recommendations remain valid; however, specific mentions of "Blob Storage SKU" are historical. See `infra/radius/recipes/azure/state-store.bicep` for current implementation.

This document explains the scaling limits you'll encounter with RadiusClaim, why they exist, how to detect when you're approaching them, and what options you have to scale beyond them.

---

## The Scaling Boundary: Expense Index Design

### What Is the Limit?

**Recommended maximum: 10,000–50,000 active expense records per state store instance.**

The practical boundary depends on your Dapr sidecar resource limits, acceptable latency thresholds, and the underlying state store performance. At 50,000+ records, you'll begin seeing latency degradation and memory pressure on Dapr sidecars. (Note: Earlier discussions of "Blob Storage SKU" apply to historical deployments; current PostgreSQL-backed state stores have different performance characteristics.)

### Why This Limit Exists

RadiusClaim stores all active expense IDs in a **single Dapr state entry** called `expenseIndex` — a JSON-serialized array of strings:

```json
["expense-001", "expense-002", "expense-003", ...]
```

Every time the API lists expenses (GET /expenses?page=1), it:
1. **Reads the entire `expenseIndex` array** from the Dapr state store via Dapr
2. **Deserializes it into memory** on the Dapr sidecar
3. **Slices and paginates** the array in-process
4. **Fetches individual expense records** for the current page

### Where Scaling Breaks Down

| Component | Bottleneck | Symptom |
|-----------|-----------|---------|
| **Blob Storage API latency** | Array size → larger blob object → slower read | GET /expenses becomes slow (>1s) even on page 1 |
| **Dapr sidecar memory** | Deserializing large array + activity task tracking | Sidecar pod runs out of memory; OOMKilled by kubelet |
| **Workflow state checkpoints** | Dapr Workflow SDK stores full history in state store | Restarting workflows with large histories times out |
| **Network payload** | Large JSON arrays serialized over HTTP | Increased latency, bandwidth costs on egress |
| **Concurrent list requests** | Multiple clients fetching the same large array simultaneously | Connection pool exhaustion on Blob Storage |

---

## How to Know When You're Hitting the Boundary

### Metric 1: Expense List Latency

**What to measure:**
- Response time for `GET /expenses?page=1` (first page, default page size)
- Monitor via Dapr logs or application instrumentation

**Warning signs:**
- Page 1 latency increases from ~50ms to >500ms
- Latency increases proportionally with expense count (not with page number)
- Sidecar logs show Dapr component latency spike at specific request times

**How to check (Kubernetes):**
```bash
# Tail expense-api Dapr sidecar logs
kubectl logs -f deployment/expense-api -c daprd -n radiusclaim-azure-radiusclaim | grep -i "state\|get\|latency"

# Check response times from application logs
kubectl logs -f deployment/expense-api -c expense-api -n radiusclaim-azure-radiusclaim | grep "GET /expenses"
```

### Metric 2: Dapr Sidecar Memory Pressure

**What to measure:**
- Memory usage of the `daprd` container in `expense-api` and `workflow-engine` pods

**Warning signs:**
- Sidecar memory climbs above 200–300 MB (default limit: 512 MB)
- Sidecar pods frequently OOMKilled
- Kubelet evicts pods due to memory pressure

**How to check:**
```bash
# View current memory of running sidecars
kubectl top pods -n radiusclaim-azure-radiusclaim --containers | grep daprd

# Check for OOMKilled events in the past 24 hours
kubectl describe nodes | grep -A 5 "OOMKilled"

# View sidecar resource limits in the app manifest
kubectl get deployment expense-api -o yaml -n radiusclaim-azure-radiusclaim | grep -A 10 "daprd.*container"
```

### Metric 3: Workflow Task Execution Time

**What to measure:**
- Time to complete an `ExpenseApprovalWorkflow` end-to-end
- Monitor via workflow activity logs

**Warning signs:**
- Workflow completion time increases from ~100ms to >2s
- Dapr Workflow SDK logs show timeout retrieving workflow state
- New expense submissions timeout before approval completes

**How to check:**
```bash
# Tail workflow-engine logs for workflow completion times
kubectl logs -f deployment/workflow-engine -c workflow-engine -n radiusclaim-azure-radiusclaim | grep -i "workflow.*complete\|activity.*duration"

# Check for state retrieval errors in Dapr sidecar
kubectl logs -f deployment/workflow-engine -c daprd -n radiusclaim-azure-radiusclaim | grep -i "error\|timeout\|failed"
```

### Metric 4: Azure Blob Storage Request Metrics

**What to measure:**
- Request latency in the Azure Portal (Storage Account → Metrics → Blob)
- Requests per second against the state blob container

**Warning signs:**
- Average latency >200ms
- Throttling errors (HTTP 429) in Dapr logs
- Increasing "Transactions" metric without corresponding endpoint capacity

**How to check (Azure Portal):**
1. Navigate to **Storage Account** → **Metrics**
2. Filter for:
   - **Metric:** `SuccessServerLatency` (Blob)
   - **Aggregation:** Average
   - **Time range:** Last 24 hours
3. Look for upward trend or sustained latency >200ms

---

## Mitigation Strategies

### Strategy 1: Archive Historical Expenses (Recommended)

**Idea:** Move older expense records out of the active index to a separate "archive" collection.

**When to use:**
- You have a natural time boundary (e.g., "approved expenses from >90 days ago")
- You want to keep the `expenseIndex` lean without redesigning state structure

**Implementation outline:**
1. Create a separate blob container `expense-archive` in the same storage account
2. Periodically (nightly batch job or scheduled activity) move old expenses:
   - Identify expenses with `status == "Approved"` and `approvedAtUtc < (now - 90 days)`
   - Copy them to the archive container
   - Remove from `expenseIndex`
   - Update workflow history separately (see below)
3. Update the API list endpoint to:
   - By default, return only "active" (non-archived) expenses
   - Optionally add a query filter `?includeArchived=true` for audit access
4. Provide a separate endpoint `/expenses/archived?date=2024-01-01` for archive queries

**Trade-offs:**
- ✅ Keeps active index small and responsive
- ✅ Expensive records stay in the system (audit/compliance)
- ❌ Adds complexity: two state collections, archival job scheduling
- ❌ Archive queries need custom logic (not auto-paginated by `expenseIndex`)

### Strategy 2: Shard the Expense Index by Employee or Date

**Idea:** Instead of a single global `expenseIndex`, maintain separate index collections per employee or per month.

**When to use:**
- Expenses are naturally partitioned (e.g., by employee, team, project)
- You can tolerate per-partition pagination (e.g., "show my expenses in March 2024")

**Implementation outline:**
1. Rename global `expenseIndex` to `expenseIndex:submitted` (to reserve the namespace)
2. Create per-employee or per-month indices:
   - `expenseIndex:submitted:emp-001`
   - `expenseIndex:submitted:2024-03`
3. When creating an expense, add the ID to **both**:
   - The period-based index (e.g., `expenseIndex:submitted:2024-03`)
   - The employee-based index (e.g., `expenseIndex:submitted:emp-001`)
4. Update the API list endpoint to:
   - Accept a filter: `?employee=emp-001` or `?month=2024-03`
   - Query the appropriate shard index instead of the global one
5. Provide a "summary" or "dashboard" endpoint that lists unique employees/periods without loading full indices

**Trade-offs:**
- ✅ Each index stays small; list operations remain fast
- ✅ Enables employee-scoped or time-scoped queries naturally
- ❌ Requires schema migration: old code expects global `expenseIndex`
- ❌ Global list endpoint (all employees, all time) becomes expensive (must union results from multiple indices)
- ❌ Adds operational burden: managing shard lifecycles, cleanup of old shards

### Strategy 3: Move to Query-Capable State Store

**Idea:** Replace Azure Blob Storage with Azure Cosmos DB or switch to a cloud-native Dapr state store that supports queries.

**When to use:**
- You need true SQL/query capabilities beyond key-value operations
- Your cloud provider's Dapr recipes already support Cosmos DB
- You're willing to change the Dapr component and recipe

**Implementation outline:**
1. Create a new Radius recipe `cosmos-state-store.bicep` with:
   - Azure Cosmos DB account (SQL API)
   - Container for expenses (partition key: `employeeId` or date)
   - Indexes on `status`, `createdAtUtc` fields
2. Define a Dapr state component for Cosmos DB (type: `state.azure.cosmosdb`)
3. Update `app.bicep` to use the new recipe
4. Refactor the API list endpoint:
   - Use Dapr Query API (not available on all stores) **or**
   - Implement direct Cosmos DB queries in your app logic (bypassing Dapr for reads)
5. Test workflow history and state recovery with Cosmos DB

**Trade-offs:**
- ✅ True querying, filtering, sorting at scale
- ✅ Cosmos DB can handle millions of documents
- ✅ Automatic indexing and partitioning
- ❌ Higher cost (Cosmos DB is 5–10x more expensive than Blob Storage)
- ❌ Changes Dapr component → requires new recipe publishing, test cycles
- ❌ Operational complexity: throughput provisioning, backup strategy
- ❌ Dapr doesn't expose rich query APIs; you may need custom query logic outside Dapr

### Strategy 4: Cache the Index in the Sidecar or Locally

**Idea:** Keep the `expenseIndex` in a local cache (Redis, in-process cache) and use the state store only for writes.

**When to use:**
- You have acceptable stale-read windows (e.g., "index is eventually consistent, refreshed every 30s")
- You can manage cache invalidation (TTL-based or event-driven)
- Sidecars have sufficient memory for the full index

**Implementation outline:**
1. Introduce a **Redis cache** in the `dev.bicep` environment:
   - Keep local Redis for dev, or use Azure Cache for Redis in production
   - Set a TTL (e.g., 60 seconds) on cached entries
2. Update the API list endpoint:
   - Check Redis for `expenseIndex:cached`
   - If cache miss, read from Dapr state store (Blob Storage)
   - Write to both Dapr and Redis on updates
3. Implement cache invalidation:
   - On new expense creation: invalidate `expenseIndex:cached`
   - On expense status update: invalidate `expenseIndex:cached`
4. Monitor cache hit ratio; adjust TTL based on latency vs. freshness trade-off

**Trade-offs:**
- ✅ Dramatically reduces latency for list operations (cache hit: <10ms)
- ✅ Minimal schema changes; works with existing state structure
- ✅ Easy to tune: adjust TTL to balance freshness vs. performance
- ❌ Index may lag behind writes by seconds (eventually consistent)
- ❌ Requires cache eviction strategy and monitoring (is Redis up? is it stale?)
- ❌ Dapr doesn't natively manage this pattern; custom app logic required

### Strategy 5: Paginate the Index at Write Time (Lazy Index)

**Idea:** Instead of storing a single array of all expense IDs, store expense indices as "index pages" (e.g., `expenseIndex:page:0`, `expenseIndex:page:1`).

**When to use:**
- You want to keep index reads bounded and predictable
- You can tolerate discovering the total expense count asynchronously

**Implementation outline:**
1. Define a fixed page size for the index (e.g., 1000 IDs per "index page")
2. On expense creation:
   - Determine which index page the new ID belongs to
   - Append it to `expenseIndex:page:X`
   - If page reaches capacity, start a new page
   - Maintain a counter `expenseIndex:totalCount` for pagination metadata
3. Update the API list endpoint:
   - Read `expenseIndex:totalCount` to compute page range
   - Based on requested page number, calculate which index pages to load
   - Read only the necessary index pages (not all of them)
4. Example: User requests page 5 with pageSize 20:
   - expenseIndex pages of 1000 IDs each → requesting IDs 80–100
   - Load `expenseIndex:page:0` (IDs 0–999)
   - Slice IDs 80–100 from that page
   - Fetch the 20 expense records

**Trade-offs:**
- ✅ Bounds index read size regardless of total expense count
- ✅ Predictable latency: always loading ≤1000 IDs
- ✅ Works with existing Dapr state store (no new infrastructure)
- ❌ More complex pagination logic; off-by-one errors possible
- ❌ Requires careful synchronization when pages fill up
- ❌ Workflow history still grows unbounded (separate mitigation needed)

### Strategy 6: Refactor Workflows to Use Durable Executors

**Idea:** Instead of storing full workflow history in the state store, use Dapr Workflow SDK's built-in state snapshotting or external durable log.

**When to use:**
- Workflow history is the bottleneck (not the expense index)
- You need to reduce state store load from workflow checkpoints

**Implementation outline:**
1. Enable Dapr Workflow `OrchestrationRuntimeState` snapshots (SDK feature):
   - Configure a snapshot interval (e.g., every 50 activities)
   - Old checkpoints are purged, keeping only the snapshot + recent history
2. Alternatively, implement a custom `IDurableTaskOrchestrationContext` wrapper:
   - Archive completed workflow runs to a separate "workflow-history" blob
   - Keep active workflows in the main state store
3. Update the Dapr component to enable state pruning if available

**Trade-offs:**
- ✅ Reduces state store size for long-running workflows
- ✅ Workflows still recoverable from snapshots
- ❌ Requires Dapr Workflow SDK upgrade or custom orchestration code
- ❌ Archive access is async (can't instantly replay a 6-month-old workflow)
- ❌ Operational complexity: monitoring snapshot health, recovery testing

---

## Combined Mitigation: Realistic Scaling Path

For RadiusClaim to handle 100K+ expenses, combine strategies:

1. **Short term (10K–50K expenses):** Apply **Strategy 1 (Archive)** + **Strategy 4 (Cache)**
   - Archive expenses >90 days old to reduce active index
   - Cache the active index in Redis to eliminate latency spikes
   - Cost: Minimal; same infrastructure, added caching layer

2. **Medium term (50K–500K expenses):** Apply **Strategy 2 (Sharding)**
   - Partition expenses by employee or month
   - Each partition remains <50K IDs
   - Cost: Modest; adds index management logic

3. **Long term (500K+ expenses):** Apply **Strategy 3 (Cosmos DB)**
   - Switch from Blob Storage to Cosmos DB
   - Enable native querying, filtering, and efficient partitioning
   - Cost: Higher ($20–100/mo depending on throughput)

---

## Monitoring and Alerting

### Key Metrics to Track

1. **expenseIndex Array Size**
   - Expose as a metric: `radiusclaim.state.expenseindex.count`
   - Alert when crossing 25K, 50K thresholds
   - Log daily to track growth trend

2. **Dapr State Latency**
   - Monitor `Dapr.StateStore.GetLatency` (sidecar metrics)
   - Alert when >300ms (baseline ~50ms for <10K records)

3. **Dapr Sidecar Memory**
   - Monitor container memory usage in Kubernetes
   - Alert when >300 MB (for 512 MB limit)

4. **Workflow Completion Time**
   - Instrument workflow activities: measure end-to-end duration
   - Alert when >2 seconds (baseline ~100ms)

5. **Blob Storage Throttling**
   - Monitor Azure Metrics: throttling errors (HTTP 429)
   - Set up Azure Monitor alert: `Count >= 10 over 5 minutes`

### Example Prometheus Alert (if using Dapr observability):

```yaml
- alert: ExpenseIndexGrowtAlert
  expr: radiusclaim_state_expenseindex_count > 50000
  for: 5m
  annotations:
    summary: "Expense index has grown to {{ $value }} records"
    description: "Consider archiving older expenses or implementing sharding"

- alert: DaprStateLatencyHigh
  expr: rate(daprd_dapr_state_get_latency_bucket[5m]) > 300
  for: 10m
  annotations:
    summary: "Dapr state latency is high ({{ $value }}ms)"
    description: "Check expense index size; consider caching or archiving"
```

---

## Recommendations for Different Deployment Scales

| Scale | Recommended Approach | Rationale |
|-------|---------------------|-----------|
| **Dev/Demo (<1K expenses)** | As-is, no changes | Scales easily on laptop or small cluster |
| **Small Production (1K–10K expenses)** | As-is + monitoring | Still fits comfortably in Blob Storage; add latency monitoring |
| **Medium Production (10K–50K expenses)** | Archive + caching | Implement archive script (nightly); add Redis cache |
| **Large Production (50K–500K expenses)** | Sharding + archiving | Partition by employee; maintain <50K per partition |
| **Enterprise (500K+ expenses)** | Cosmos DB + sharding | Switch state store; enable querying; plan for multi-region |

---

## Testing Your Scaling Limits

### Load Test: Bulk Expense Creation

```bash
# Generate 10,000 test expenses (takes ~5 minutes)
for i in {1..10000}; do
  curl -X POST http://localhost:5000/expenses \
    -H "Content-Type: application/json" \
    -d "{
      \"amount\": $(( RANDOM % 500 + 1 )),
      \"description\": \"Test expense $i\",
      \"employeeId\": \"emp-$(( i % 10 ))\",
      \"category\": \"test\"
    }" &
  [ $(( (i+1) % 100 )) -eq 0 ] && wait  # Batch requests
done
wait
```

### Measure Latency

```bash
# Measure GET /expenses latency across load
for i in {1..100}; do
  time curl http://localhost:5000/expenses?page=1 > /dev/null 2>&1
done | grep real | awk '{sum+=$2; count++} END {print "Average:", sum/count}'
```

### Monitor During Load

```bash
# In another terminal, watch Dapr sidecar memory
watch -n 1 "kubectl top pod <expense-api-pod-name> -n <ns> --containers | grep daprd"
```

---

## Summary

RadiusClaim can reliably handle **10,000–50,000 active expenses** with the current architecture. Beyond that, apply the mitigation strategies based on your scale, operational complexity tolerance, and budget. Start with archiving and caching; upgrade to sharding or a query-capable store as you grow.

For questions or issues related to scaling, consult the team's architecture decision log (`.squad/decisions.md`) or open an issue tagged `scaling`.

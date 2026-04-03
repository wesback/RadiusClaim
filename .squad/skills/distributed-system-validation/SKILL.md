---
name: "distributed-system-validation"
description: "Script-based integration validation for distributed systems that require runtime behavior proof"
domain: "testing"
confidence: "high"
source: "karen-phase7"
---

## Context

Use this when a distributed application needs integration validation but:
- No test framework exists in the repository
- The system requires runtime components (sidecars, message brokers, state stores)
- Validation must prove **distributed behavior**, not just process startup
- Target audience includes platform engineers or operators (not just developers)

## Patterns

### Prefer executable validation over documentation alone

- A checklist is necessary but not sufficient for distributed systems
- Create a standalone validation script that can be run by any user
- Extract and generalize existing CI/CD validation logic rather than inventing new patterns
- Use common shell tools (bash, curl, jq) that ops teams already have

### Validate runtime behavior, not just component availability

- **Anti-pattern:** Check that services return HTTP 200 and call it validated
- **Better:** Submit requests, poll for asynchronous outcomes, verify state transitions
- Prove that distributed coordination actually works (workflows execute, messages deliver, state persists)
- Include boundary cases and threshold decisions, not just happy paths

### Structure validation in logical phases

- Health check (connectivity, basic availability)
- Happy path flow (primary use case)
- Edge case flow (thresholds, holds, denials)
- Boundary case validation (exact threshold values)
- Summary with clear pass/fail and actionable diagnostics

### Design for both manual and automated execution

- Script should work standalone for troubleshooting
- Integrate the same logic into CI/CD pipelines
- Let CI pair the shared flow-validation script with platform-specific evidence gathering (for example, `kubectl logs` on Kubernetes or platform-native log commands elsewhere)
- Emit an optional machine-readable artifact (expense IDs, correlation IDs, summary counts) so downstream CI steps can verify logs without reimplementing the flow checks
- Provide clear usage documentation and examples
- Return meaningful exit codes (0 = success, non-zero = failure)
- Use colored output for human readability, but ensure it works in CI logs

### Validate status transitions over time

- Distributed systems are asynchronous; validation must poll for eventual outcomes
- Use reasonable timeouts (30-60 seconds per transition)
- Show progress indicators during waiting (dots, spinners)
- Fail fast on connectivity issues, but wait patiently for distributed coordination

## Examples

### Validation script structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# Parse arguments and validate prerequisites
API_URL="${1%/}"
command -v jq >/dev/null || { echo "jq required"; exit 1; }

# Health check phase
check "API endpoint is accessible"
if curl -sf "${API_URL}/healthz" | jq -e '.status == "ok"'; then
    pass
else
    fail "Health check failed"
fi

# Happy path flow
submit_response=$(curl -sf -X POST "${API_URL}/items" -d '{"amount": 50}')
item_id=$(jq -r '.id' <<<"$submit_response")

check "Item progresses to completed status"
wait_for_status "$item_id" "completed" 30
if [ $? -eq 0 ]; then pass; else fail "Timeout"; fi

# Exit with summary
if [ $FAILURES -eq 0 ]; then
    echo "All validations PASSED"
    exit 0
else
    echo "Validation FAILED with $FAILURES error(s)"
    exit 1
fi
```

### Integration into CI/CD

```yaml
- name: Run end-to-end validation
  run: |
    api_fqdn=$(get_deployed_api_url)
    VALIDATION_OUTPUT_PATH="$RUNNER_TEMP/validation.json" ./scripts/validate-deployment.sh "https://$api_fqdn"

- name: Verify notification evidence
  run: |
    expense_id=$(jq -r '.autoApprove.expenseId' "$RUNNER_TEMP/validation.json")
    correlation_id=$(jq -r '.autoApprove.correlationId' "$RUNNER_TEMP/validation.json")
    logs=$(kubectl logs deployment/notification-svc -c notification-svc --tail=200)
    grep -q "ExpenseId=$expense_id" <<<"$logs"
    grep -q "CorrelationId=$correlation_id" <<<"$logs"
```

### Polling for asynchronous outcomes

```bash
wait_for_status() {
    local item_id="$1"
    local expected_status="$2"
    local max_attempts="${3:-30}"

    for attempt in $(seq 1 "$max_attempts"); do
        sleep 2
        current=$(curl -sf "${API_URL}/items/${item_id}" | jq -r '.status')
        if [ "$current" = "$expected_status" ]; then
            return 0
        fi
        echo -n "."  # Progress indicator
    done
    return 1
}
```

## Anti-Patterns

- **Checking only process startup:** "The container is running" ≠ "The distributed system works"
- **Skipping asynchronous validation:** If workflows/messages are async, validation must wait for them
- **Assuming immediate consistency:** Distributed systems have propagation delays; poll with timeouts
- **Adding a test framework prematurely:** If no tests exist and the sample is infrastructure-focused, a script may be more appropriate than xUnit/Jest/etc.
- **Inventing new infrastructure:** If the project constraint is "use existing tooling only," do not add test frameworks just to satisfy a phase gate

## When Not to Use This Pattern

- **When a test framework already exists:** Prefer extending existing tests over creating standalone scripts
- **When the system is not distributed:** Simple CRUD APIs may not need distributed validation; unit/integration tests suffice
- **When the audience is primarily developers:** Developers may expect xUnit/pytest/Mocha patterns; scripts may feel unfamiliar

## Related Skills

- `phase-gate-validation`: Defines when to use evidence-based validation vs. automated tests
- `dotnet-dapr-state-api`: Context for distributed Dapr-based apps that this validation pattern targets

# Observability Configuration

## Overview

RadiusClaim services are instrumented with **OpenTelemetry** to collect distributed traces and logs. Traces are exported to **Jaeger** for local development and can be integrated with **Application Insights** for cloud deployments.

## Services Instrumented

- **expense-api**: Main REST API for expense submission and approval
- **workflow-engine**: Dapr Workflow orchestration service
- **notification-svc**: Pub/Sub notification service

## Local Development Setup

### Jaeger Agent (Development)

For local development, run Jaeger in Docker:

```bash
docker run --rm \
  -p 6831:6831/udp \
  -p 6832:6832/udp \
  -p 16686:16686 \
  jaegertracing/all-in-one:latest
```

This exposes:
- **Jaeger UI**: http://localhost:16686 — browse traces and service topology
- **Agent gRPC**: localhost:6831 — where services send spans

### Environment Variables

Set these variables to override Jaeger agent defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `JAEGER_AGENT_HOST` | `localhost` | Jaeger agent hostname |
| `JAEGER_AGENT_PORT` | `6831` | Jaeger agent UDP port |

Example:

```bash
export JAEGER_AGENT_HOST=localhost
export JAEGER_AGENT_PORT=6831
```

If Jaeger is unavailable, services gracefully log a warning and continue operating.

## Cloud Deployment (Future)

Future versions will support Azure Application Insights for distributed tracing and logging in production.

### Key Correlation IDs

Services correlate requests across the system using the **X-Correlation-ID** header:

```
GET /workflows/{instanceId}
X-Correlation-ID: abc-123-def-456
```

This header is:
1. Extracted by each service
2. Passed to downstream service-invocation calls (via Dapr)
3. Logged in all trace spans

This enables end-to-end tracing of expense submission → approval → reimbursement workflows.

## Instrumentation Details

### What Gets Traced

- **HTTP requests/responses** (asp: incoming; http: outgoing)
- **Dapr service invocations** (logged via correlation IDs)
- **Workflow state transitions** (manually instrumented)

### Limitations

- Currently, traces are **sampled** at 100% (all requests). In production, adjust via OpenTelemetry configuration.
- **Dapr gRPC calls** (workflow client) are not automatically instrumented; correlation IDs are manually attached.

## Verification

To verify tracing is working:

1. Ensure Jaeger is running:
   ```bash
   curl http://localhost:6831/health || echo "Jaeger not responding"
   ```

2. Submit an expense and check **Jaeger UI** for the trace:
   ```bash
   curl -X POST http://localhost:5001/expenses \
     -H "Content-Type: application/json" \
     -d '{"expenseId":"exp-1","amount":100,"currency":"USD","description":"Test"}'
   ```

3. Open http://localhost:16686 → search for service name (e.g., "expense-api") → view traces.

## Troubleshooting

### "Jaeger connection refused"

- Verify Jaeger container is running: `docker ps | grep jaeger`
- Check logs: `docker logs <jaeger-container-id>`
- Verify port is correct: `netstat -an | grep 6831` (or use `ss` on Linux)

### No traces appearing in Jaeger UI

- Check service logs for "Traces are exported to Jaeger" startup message
- Confirm `JAEGER_AGENT_HOST` and `JAEGER_AGENT_PORT` match your setup
- Manually trigger a request (submit an expense)
- Refresh Jaeger UI

### High latency in traces

- Local Dapr sidecars add latency due to inter-process communication
- This is expected in development; cloud deployments will show real-world latency

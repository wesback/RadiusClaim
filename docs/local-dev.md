# Local Development Guide

> **Supported local path:** run the services directly with Dapr sidecars and the checked-in `infra/dapr/local` overlays. The repo does **not** currently ship a supported local Radius recipe set, so this guide avoids `infra/radius/environments/local.bicep`.

## Overview

Local development keeps the app contract the same while swapping in lightweight local dependencies:

| Concern | Local development path |
|---|---|
| State store | Redis via Dapr |
| Pub/Sub | Redis via Dapr |
| Secrets | Local file secret store via Dapr |
| Workflow orchestration | Dapr Workflow runtime |

This is the fastest way to iterate on the app code, hosted web UI, and workflow behavior without provisioning Azure resources.

## Prerequisites

- Docker Desktop or equivalent container runtime
- .NET SDK matching the repo's `global.json`
- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/)

## 1. Start local dependencies

```bash
docker compose -f infra/dapr/local/docker-compose.yaml up -d
```

This starts the local dependencies referenced by the checked-in Dapr component files under `infra/dapr/local`.

## 2. Run the services with Dapr

Start each service in its own terminal.

### Terminal 1 — workflow-engine

```bash
dapr run --app-id workflow-engine --app-port 5299 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/workflow-engine/WorkflowEngine.csproj
```

### Terminal 2 — expense-api

```bash
dapr run --app-id expense-api --app-port 5062 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/expense-api/ExpenseApi.csproj
```

### Terminal 3 — notification-svc (optional but useful)

```bash
dapr run --app-id notification-svc --app-port 5238 --resources-path ./infra/dapr/local -- \
  dotnet run --project src/notification-svc/NotificationSvc.csproj
```

## 3. Open the demo UI

Once `expense-api` is running with its Dapr sidecar, open:

```text
http://localhost:5062/app
```

## 4. Validate the local flow

- Submit a small expense and confirm it auto-approves
- Submit a larger expense and confirm it enters manual review
- If `notification-svc` is running, watch its console output for published events

## Troubleshooting

### `/app` loads but actions fail

Make sure both `expense-api` and `workflow-engine` are running with Dapr sidecars. A plain `dotnet run` without `dapr run` only starts the ASP.NET host.

### Redis-backed components do not load

Restart the local dependencies:

```bash
docker compose -f infra/dapr/local/docker-compose.yaml down
docker compose -f infra/dapr/local/docker-compose.yaml up -d
```

Then restart the Dapr sidecars.

### You want the full Radius + Azure path instead

Use `scripts/bootstrap.sh` and the Kubernetes-first walkthrough in [`docs/end-to-end-setup-walkthrough.md`](./end-to-end-setup-walkthrough.md). That is the supported deployment path for the repo's Radius model.

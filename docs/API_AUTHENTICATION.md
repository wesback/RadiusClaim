# API Authentication — Microsoft Entra ID (OAuth 2.0)

RadiusClaim uses **Microsoft Entra ID** (formerly Azure AD) JWT bearer tokens to protect approval actions. The expense-api validates tokens issued by Entra ID on protected endpoints; submission and read endpoints are public.

---

## Endpoint Authentication Matrix

| Endpoint | Method | Auth Required | Reason |
|----------|--------|:------------:|--------|
| `/expenses/` | POST | ❌ | Anyone can submit an expense |
| `/expenses/` | GET | ❌ | Public listing |
| `/expenses/{id}` | GET | ❌ | Public detail view |
| `/expenses/{id}/workflow` | GET | ❌ | Public workflow status |
| `/expenses/{id}/approve` | POST | ✅ | Only authorized users may approve |
| `/expenses/{id}/reject` | POST | ✅ | Only authorized users may reject |

Protected endpoints return `401 Unauthorized` when called without a valid bearer token.

---

## Configuration

Authentication is configured via `appsettings.json` or environment variables.

### appsettings.json

```json
{
  "AzureAd": {
    "Authority": "https://login.microsoftonline.com/{tenant-id}",
    "Audience": "api://{application-id}"
  }
}
```

### Environment variables (Kubernetes / container)

```bash
AzureAd__Authority=https://login.microsoftonline.com/{tenant-id}
AzureAd__Audience=api://{application-id}
```

> **Production requirement:** Both `Authority` and `Audience` must be set in non-Development environments. The API will fail to start if they are missing — this is intentional to prevent misconfigured deployments.

### Development defaults

In `Development` mode, the API falls back to permissive defaults if config is absent:

- Authority: `https://login.microsoftonline.com/common`
- Audience: `https://radiusclaim.azurewebsites.net/api`

---

## Entra ID Setup (App Registration)

To issue tokens for this API, register an application in Microsoft Entra ID:

1. **Register the API application**
   - Go to [Azure Portal → App registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
   - Click **New registration**
   - Name: `RadiusClaim API` (or similar)
   - Supported account types: **Single tenant** (recommended)
   - Click **Register**

2. **Expose an API**
   - Under **Expose an API**, click **Set** next to "Application ID URI"
   - Accept the default (`api://{client-id}`) or set a custom URI
   - Add a scope: `Expenses.Approve` (used by approve/reject endpoints)

3. **Note the values**
   - **Authority**: `https://login.microsoftonline.com/{tenant-id}`
   - **Audience**: The Application ID URI (e.g., `api://{client-id}`)

4. **Configure the API**
   - Set `AzureAd:Authority` and `AzureAd:Audience` to the values above

---

## Service-to-Service Authentication (Client Credentials)

For automated callers (scripts, other services), use the OAuth 2.0 client credentials flow:

1. **Register a client application** in Entra ID (or reuse an existing one)
2. **Create a client secret** or configure a certificate
3. **Grant API permissions**: Add the `Expenses.Approve` scope from the API registration
4. **Request a token** using MSAL or a direct HTTP call

### Token acquisition with Azure CLI (testing)

```bash
# Get a token for the RadiusClaim API
TOKEN=$(az account get-access-token \
  --resource "api://{application-id}" \
  --query accessToken -o tsv)

# Call a protected endpoint
curl -s -X POST "http://localhost:5062/expenses/{id}/approve" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason": "Approved by finance"}'
```

### Token acquisition with MSAL (.NET)

```csharp
using Azure.Identity;
using Microsoft.Identity.Client;

var app = ConfidentialClientApplicationBuilder
    .Create("{client-id}")
    .WithClientSecret("{client-secret}")
    .WithAuthority("https://login.microsoftonline.com/{tenant-id}")
    .Build();

var result = await app.AcquireTokenForClient(
    scopes: new[] { "api://{api-application-id}/.default" })
    .ExecuteAsync();

// Use result.AccessToken as Bearer token
httpClient.DefaultRequestHeaders.Authorization =
    new AuthenticationHeaderValue("Bearer", result.AccessToken);
```

---

## Testing Authentication Locally

### Without a real Entra tenant

For local development, the API starts with permissive defaults. You can:

- Call **anonymous endpoints** (`POST /expenses`, `GET /expenses`) directly
- Call **protected endpoints** by skipping auth validation (set `ASPNETCORE_ENVIRONMENT=Development`)

### With curl

```bash
# Submit an expense (no auth required)
curl -s -X POST http://localhost:5062/expenses/ \
  -H "Content-Type: application/json" \
  -d '{
    "employeeId": "emp-123",
    "amount": 42.50,
    "currency": "USD",
    "description": "Team lunch"
  }'

# List expenses (no auth required)
curl -s http://localhost:5062/expenses/
```

### Unit tests

The test suite (`src/ExpenseApi.Tests/OAuth2AuthenticationTests.cs`) covers:

- Anonymous access to public endpoints (submit, list, detail, workflow)
- 401 rejection on protected endpoints (approve, reject) without tokens
- Bearer token processing with valid JWT format

---

## Workload Identity (Kubernetes)

In Kubernetes deployments, service-to-service auth uses **Azure Workload Identity** instead of client secrets. The bootstrap script (`scripts/bootstrap.sh`) configures:

- A managed identity (`radiusclaim-workload-identity`)
- Federated identity credentials linked to the AKS OIDC issuer
- Service account annotations for workload identity injection

See [WORKLOAD_IDENTITY_MIGRATION.md](../WORKLOAD_IDENTITY_MIGRATION.md) for the platform-layer identity setup.

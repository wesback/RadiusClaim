# Decision: Auth Config Portability (Issue #44 + #52)

**Author:** Daisy (Lead)
**Date:** 2026-07
**Status:** Implemented

## Context

Issues #44 and #52 requested removing hardcoded Azure subscription IDs and documenting API authentication.

## Findings

1. **No hardcoded subscription IDs in shipped code.** Scripts already use `az account show` for dynamic resolution. Bicep files accept parameters. The parameters.json has empty values. Issue #44 was effectively already handled at the infra layer.

2. **Auth audience was hardcoded in Program.cs.** The fallback `https://radiusclaim.azurewebsites.net/api` was a portability blocker. This was the real config gap.

3. **Auth tests had drift.** `OAuth2AuthenticationTests` asserted 401 for unauthenticated `POST /expenses`, but the route is intentionally anonymous. `ExpenseApiValidationTests` contradicted this by calling the same endpoint without auth and expecting success.

## Decisions

- **Fail-fast in production** if `AzureAd:Authority` or `AzureAd:Audience` are not set. Dev mode keeps permissive defaults.
- **Use standard ASP.NET config binding** (`AzureAd__Authority` env vars) — no custom env var names.
- **POST /expenses remains anonymous.** Tests now match this design. Approve/reject remain protected.
- **Created `docs/API_AUTHENTICATION.md`** — the referenced-but-missing doc file.

## Team Impact

- **Karen (Tester):** Auth tests updated. One remaining test (`PostExpense_WithInvalidBearerToken_Returns401Unauthorized`) may need review — its behavior depends on JwtBearer middleware edge cases for invalid tokens on anonymous endpoints.
- **Graham/Pete (Platform):** No infra changes needed — subscription parameterization was already correct.
- **Eddie (Docs):** New auth doc added; README updated with link.

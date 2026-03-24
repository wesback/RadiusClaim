# Phase 7 Validation Checklist

> **Owner:** Karen (Tester)  
> **Phase:** 7 — Final Validation & Demo Readiness  
> **Updated:** 2026-03-24

---

## Purpose

This checklist ensures the RadiusClaim sample is production-ready for demo and external sharing. Phase 7 validates **distributed system behavior** end-to-end, not just process startup.

---

## Pre-Validation Requirements

Before running Phase 7 validation, ensure:

- [ ] All Phases 1–6 are complete and approved
- [ ] Application code builds without errors or warnings
- [ ] Radius models parse cleanly (`az bicep build` passes)
- [ ] Deployment is live (either Radius-first or ACA fallback)
- [ ] expense-api is accessible via public endpoint or local `kubectl port-forward`

---

## Validation Methods

Phase 7 supports **three validation levels**:

### 1. Automated Script Validation (Recommended)

**Tool:** `scripts/validate-deployment.sh`

**What it validates:**
- Health endpoint accessibility
- $50 auto-approve flow (Submitted → Approved → Reimbursed)
- $150 manual-review flow (Submitted → ManualReviewRequested)
- $100.00 boundary case (must enter manual review, not auto-approve)
- Correct status transitions and amount preservation

**How to run:**
```bash
# Public endpoint
./scripts/validate-deployment.sh https://<expense-api-fqdn>

# Or via a local port-forward for Radius-first deployments
./scripts/validate-deployment.sh http://127.0.0.1:8080
```

**Expected result:**
- All checks PASS
- Exit code 0
- Summary confirms distributed behavior validation

**What this proves:**
- State persistence works across services
- Workflow orchestration executes correctly
- Service invocation delivers workflow requests
- Approval thresholds are correct
- Boundary case ($100.00) handled correctly

### 2. GitHub Actions CI/CD Validation (Automated)

**Workflow:** `.github/workflows/deploy-azure.yml`

**What it validates:**
- Same checks as the standalone script
- Integrated into deployment pipeline
- Validates both Radius-first and ACA fallback paths
- Checks notification-svc logs for pub/sub evidence

**Trigger:** Runs automatically on every deployment

**Expected result:**
- `validate` job passes (build, test)
- `deploy-*` job completes successfully
- End-to-end validation step confirms $50 and $150 flows

### 3. Manual Demo Walkthrough (Human-Observable)

**Guide:** `docs/phase-7-demo-walkthrough.md`

**What it validates:**
- Complete user-facing story
- Log evidence in notification-svc
- Correlation traceability end-to-end
- Human-understandable failure messages

**How to run:**
- Follow the step-by-step guide
- Submit $50 and $150 expenses manually via curl
- Poll for status transitions
- Check Azure Container Apps logs for notification events

**Expected result:**
- Both flows complete as documented
- Logs show ExpenseApproved and ManualReviewRequested events
- CorrelationId appears consistently across submission → approval → notification

---

## Phase 7 Exit Criteria

Phase 7 is **APPROVED** when all of the following are true:

### Build & Parse Validation

- [x] `dotnet build RadiusClaim.slnx --nologo` passes with zero errors/warnings
- [x] `az bicep build --file infra/radius/app.bicep` parses without errors
- [ ] No test projects exist (tests deferred to future phases per project scope)

### Distributed System Validation (Automated Script)

- [ ] Health endpoint returns `{ "status": "ok" }`
- [ ] $50 expense progresses: Submitted → Approved → Reimbursed
- [ ] $150 expense progresses: Submitted → ManualReviewRequested (and stays there)
- [ ] $100.00 expense enters ManualReviewRequested (not auto-approved)
- [ ] All amounts preserved correctly in final records
- [ ] Script exits with code 0 (all checks passed)

### Distributed System Validation (CI/CD)

- [ ] GitHub Actions workflow completes successfully
- [ ] Deployment provisions all three services
- [ ] End-to-end validation step passes in workflow logs
- [ ] Notification logs show both ExpenseApproved and ManualReviewRequested events

### Documentation & Demo Readiness

- [ ] README accurately describes the sample's capabilities
- [ ] Phase 7 demo walkthrough is clear and executable
- [ ] Troubleshooting section covers common deployment issues
- [ ] Boundary case ($100.00) explicitly documented

### Release Confidence

- [ ] Sample demonstrates meaningful distributed behavior (not just startup)
- [ ] Auto-approve and manual-review flows are observable and traceable
- [ ] No hand-waved edge cases or unexplained failure paths
- [ ] Validation can be repeated by any team member or external user

---

## Release-Blocking Gaps

If any of the following are discovered, Phase 7 cannot pass:

1. **Auto-approve threshold violation:** $50 does not auto-approve, or $100 does auto-approve
2. **Boundary case failure:** $100.00 exactly auto-approves instead of entering manual review
3. **Status stuck:** Expenses remain "Submitted" and never progress to workflow outcomes
4. **Missing distributed behavior:** State or workflow invocation not working (proves only HTTP startup, not Dapr integration)
5. **Script validation failure:** `validate-deployment.sh` exits with non-zero code
6. **CI/CD validation failure:** GitHub Actions end-to-end validation step fails

---

## Known Non-Blocking Issues

The following are **out of scope** for Phase 7 and do not block approval:

- **Notification log delay:** Logs may take 10–20 seconds to appear (this is normal for pub/sub propagation)
- **No real notification delivery:** Sample logs notifications instead of sending email/Slack/Teams (by design)
- **No automated integration test suite:** Script-based validation is sufficient for this phase
- **No multi-cloud validation:** Sample targets Azure only (Dapr code is portable, but only Azure deployment is tested)

---

## Evidence Required for Approval

To approve Phase 7, Karen (Tester) requires:

1. **Fresh validation script execution:** Run `./scripts/validate-deployment.sh` against a live deployment and provide full output
2. **CI/CD workflow logs:** Provide link to successful GitHub Actions run showing end-to-end validation
3. **Manual demo confirmation:** At least one team member completes the demo walkthrough and confirms both flows work as documented

---

## Phase 7 Approval Authority

**Approver:** Karen (Tester)

**Rejection criteria:**
- Any release-blocking gap discovered
- Validation script fails
- CI/CD end-to-end validation fails
- Boundary case ($100.00) handled incorrectly

**Approval format:**
```
Phase 7 APPROVED [timestamp]

Evidence:
- Validation script: [output or link]
- CI/CD run: [GitHub Actions run link]
- Manual demo: [confirmed by: name]

Karen (Tester)
```

---

## Next Steps After Phase 7

Once Phase 7 passes:

1. **Sample release:** RadiusClaim is demo-ready and can be shared externally
2. **Pattern library:** This sample becomes a reference implementation for Dapr + Radius
3. **Future enhancements:** Integration tests, multi-cloud validation, advanced features

---

## Revision History

| Date       | Change                                               | Author |
|------------|------------------------------------------------------|--------|
| 2026-03-24 | Initial Phase 7 validation checklist and script      | Karen  |

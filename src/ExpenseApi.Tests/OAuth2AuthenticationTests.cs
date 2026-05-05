using System.Net;
using System.Net.Http.Json;
using RadiusClaim.Contracts;
using Xunit;

namespace ExpenseApi.Tests;

/// <summary>
/// Approval-path contract tests for expense-api.
/// These focus on observable behavior: anonymous manual decisions and truthful failure semantics.
/// </summary>
public sealed class OAuth2AuthenticationTests
{
    private static ExpenseRecord ManualReviewRecord(string expenseId = "exp-manual-1") =>
        new(
            ExpenseId: expenseId,
            CorrelationId: $"corr-{expenseId}",
            EmployeeId: "emp-review",
            Amount: 250m,
            Currency: "USD",
            Description: "Needs manual review",
            Status: ExpenseStatus.ManualReviewRequested,
            SubmittedAtUtc: DateTimeOffset.UtcNow.AddMinutes(-5),
            LastUpdatedAtUtc: DateTimeOffset.UtcNow.AddMinutes(-5));

    [Fact]
    public async Task PostApproveExpense_WithoutBearerToken_AcceptsAnonymousDecision()
    {
        var original = ManualReviewRecord("exp-anon-approve");
        await using var host = ExpenseApiTestHost.Create(
            seedRecord: original,
            workflowDecisionStatusCode: HttpStatusCode.Accepted);

        var response = await host.Client.PostAsJsonAsync("/expenses/exp-anon-approve/approve", new
        {
            reason = "Approved for reimbursement"
        });

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Equal(1, host.Sidecar.DecisionRequestCount);
        AssertRecordUnchanged(host.GetExpense("exp-anon-approve"), original);
    }

    [Fact]
    public async Task PostRejectExpense_WithoutBearerToken_AcceptsAnonymousDecision()
    {
        var original = ManualReviewRecord("exp-anon-reject");
        await using var host = ExpenseApiTestHost.Create(
            seedRecord: original,
            workflowDecisionStatusCode: HttpStatusCode.Accepted);

        var response = await host.Client.PostAsJsonAsync("/expenses/exp-anon-reject/reject", new
        {
            reason = "Rejected for missing receipt"
        });

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Equal(1, host.Sidecar.DecisionRequestCount);
        AssertRecordUnchanged(host.GetExpense("exp-anon-reject"), original);
    }

    [Fact]
    public async Task PostApproveExpense_WhenWorkflowReturnsNotFound_DoesNotMutateApprovalAuditFields()
    {
        var original = ManualReviewRecord("exp-workflow-404");
        await using var host = ExpenseApiTestHost.Create(
            seedRecord: original,
            workflowDecisionStatusCode: HttpStatusCode.NotFound);

        var response = await host.Client.PostAsJsonAsync("/expenses/exp-workflow-404/approve", new
        {
            reason = "Approved by reviewer"
        });

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);

        AssertRecordUnchanged(host.GetExpense("exp-workflow-404"), original);
    }

    [Fact]
    public async Task PostRejectExpense_WhenWorkflowReturnsConflict_DoesNotMutateApprovalAuditFields()
    {
        var original = ManualReviewRecord("exp-workflow-409");
        await using var host = ExpenseApiTestHost.Create(
            seedRecord: original,
            workflowDecisionStatusCode: HttpStatusCode.Conflict);

        var response = await host.Client.PostAsJsonAsync("/expenses/exp-workflow-409/reject", new
        {
            reason = "Policy violation"
        });

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);

        AssertRecordUnchanged(host.GetExpense("exp-workflow-409"), original);
    }

    [Fact]
    public async Task PostApproveExpense_WhenWorkflowSignalFails_DoesNotMutateApprovalAuditFields()
    {
        var original = ManualReviewRecord("exp-workflow-500");
        await using var host = ExpenseApiTestHost.Create(
            seedRecord: original,
            workflowDecisionStatusCode: HttpStatusCode.InternalServerError);

        var response = await host.Client.PostAsJsonAsync("/expenses/exp-workflow-500/approve", new
        {
            reason = "Approved by reviewer"
        });

        Assert.Equal(HttpStatusCode.BadGateway, response.StatusCode);

        AssertRecordUnchanged(host.GetExpense("exp-workflow-500"), original);
    }

    private static void AssertRecordUnchanged(ExpenseRecord? stored, ExpenseRecord original)
    {
        Assert.NotNull(stored);
        Assert.Equal(original.Status, stored!.Status);
        Assert.Equal(original.ApprovedBy, stored.ApprovedBy);
        Assert.Equal(original.ApprovedAt, stored.ApprovedAt);
        Assert.Equal(original.RejectionReason, stored.RejectionReason);
    }
}

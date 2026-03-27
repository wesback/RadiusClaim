using RadiusClaim.Contracts;
using Dapr.Client;
using Dapr.Workflow;
using Microsoft.Extensions.Options;
using WorkflowEngine.Models;

namespace WorkflowEngine.Activities;

internal sealed class ApproveExpenseActivity(
    DaprClient daprClient,
    IOptions<ApprovalOptions> approvalOptions,
    ILogger<ApproveExpenseActivity> logger) : WorkflowActivity<ExpenseSubmission, ApprovalDecision>
{
    private const string AutoApprovalDecisionSource = "AutoApprovedUnderThreshold";
    private const string ManualReviewDecisionSource = "ManualReviewThresholdReached";

    public override async Task<ApprovalDecision> RunAsync(WorkflowActivityContext context, ExpenseSubmission input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var record = await daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.StateStore,
            RadiusClaimDapr.StateKeys.Expense(input.ExpenseId));

        if (record is null)
        {
            throw new InvalidOperationException(
                $"Expense '{input.ExpenseId}' was not found in state store before approval.");
        }

        if (!string.Equals(record.CorrelationId, input.CorrelationId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Expense '{input.ExpenseId}' correlation mismatch. Expected '{input.CorrelationId}', found '{record.CorrelationId}'.");
        }

        var threshold = approvalOptions.Value.ThresholdUsd;
        var isAutoApproved = input.Amount < threshold;
        var nextStatus = isAutoApproved ? ExpenseStatus.Approved : ExpenseStatus.ManualReviewRequested;
        var decision = new ApprovalDecision(
            nextStatus,
            isAutoApproved ? AutoApprovalDecisionSource : ManualReviewDecisionSource,
            isAutoApproved ? NotificationEventType.ExpenseApproved : NotificationEventType.ManualReviewRequested);

        if (record.Status is ExpenseStatus.Reimbursed && isAutoApproved)
        {
            return decision;
        }

        if (record.Status == nextStatus)
        {
            return decision;
        }

        if (record.Status != ExpenseStatus.Submitted)
        {
            throw new InvalidOperationException(
                $"Expense '{input.ExpenseId}' cannot transition from '{record.Status}' to '{nextStatus}'.");
        }

        var updatedRecord = record with
        {
            Status = nextStatus,
            LastUpdatedAtUtc = DateTimeOffset.UtcNow
        };

        await daprClient.SaveStateAsync(
            RadiusClaimDapr.Components.StateStore,
            RadiusClaimDapr.StateKeys.Expense(input.ExpenseId),
            updatedRecord);

        logger.LogInformation(
            "Expense '{ExpenseId}' moved to '{Status}' for workflow '{InstanceId}'.",
            input.ExpenseId,
            nextStatus,
            context.InstanceId);

        return decision;
    }
}

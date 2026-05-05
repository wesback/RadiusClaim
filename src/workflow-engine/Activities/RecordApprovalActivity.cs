using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Client;
using Dapr.Workflow;
using WorkflowEngine.Models;

namespace WorkflowEngine.Activities;

/// <summary>
/// Idempotent activity that transitions an expense from ManualReviewRequested → Approved
/// in the state store. Called by the workflow after a human approver signals approval.
/// Uses ConsistencyMode.Strong to ensure approval transitions are visible to concurrent
/// operations, matching expense-api consistency practices.
/// </summary>
internal sealed class RecordApprovalActivity(
    DaprClient daprClient,
    ILogger<RecordApprovalActivity> logger) : WorkflowActivity<ApprovalRecordInput, bool>
{
    public override async Task<bool> RunAsync(WorkflowActivityContext context, ApprovalRecordInput input)
    {
        ArgumentNullException.ThrowIfNull(input);

        if (string.IsNullOrWhiteSpace(input.ExpenseId))
        {
            throw new ArgumentException("ExpenseId is required.", nameof(input));
        }

        var normalizedId = input.ExpenseId.Trim();
        var decisionTimeUtc = input.DecisionTimeUtc == default
            ? DateTimeOffset.UtcNow
            : input.DecisionTimeUtc.ToUniversalTime();
        var stateKey = RadiusClaimDapr.StateKeys.Expense(normalizedId);

        var record = await daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.StateStore,
            stateKey,
            consistencyMode: ConsistencyMode.Strong);

        if (record is null)
        {
            throw new InvalidOperationException(
                $"Expense '{normalizedId}' was not found in state store before recording approval.");
        }

        if (!string.Equals(record.CorrelationId, input.CorrelationId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Expense '{normalizedId}' correlation mismatch. Expected '{input.CorrelationId}', found '{record.CorrelationId}'.");
        }

        // Idempotent: already approved or further along is fine.
        if (record.Status is ExpenseStatus.Approved or ExpenseStatus.Reimbursed)
        {
            logger.LogInformation(
                "Expense '{ExpenseId}' is already '{Status}' — skipping approval record (idempotent) for workflow '{InstanceId}'.",
                normalizedId,
                record.Status,
                context.InstanceId);
            return true;
        }

        if (record.Status != ExpenseStatus.ManualReviewRequested)
        {
            throw new InvalidOperationException(
                $"Expense '{normalizedId}' cannot transition to Approved from status '{record.Status}'. " +
                "Only ManualReviewRequested expenses can be manually approved.");
        }

        var updatedRecord = record with
        {
            Status = ExpenseStatus.Approved,
            RejectionReason = null,
            ApprovedBy = null,
            ApprovedAt = decisionTimeUtc,
            LastUpdatedAtUtc = decisionTimeUtc
        };

        await daprClient.SaveStateAsync(
            RadiusClaimDapr.Components.StateStore,
            stateKey,
            updatedRecord,
            stateOptions: new StateOptions { Consistency = ConsistencyMode.Strong });

        logger.LogInformation(
            "Expense '{ExpenseId}' recorded as Approved (manual) at {DecisionTimeUtc} for workflow '{InstanceId}'.",
            normalizedId,
            decisionTimeUtc,
            context.InstanceId);

        return true;
    }
}

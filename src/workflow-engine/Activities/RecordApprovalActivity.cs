using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Client;
using Dapr.Workflow;

namespace WorkflowEngine.Activities;

/// <summary>
/// Idempotent activity that transitions an expense from ManualReviewRequested → Approved
/// in the state store. Called by the workflow after a human approver signals approval.
/// </summary>
internal sealed class RecordApprovalActivity(
    DaprClient daprClient,
    ILogger<RecordApprovalActivity> logger) : WorkflowActivity<string, bool>
{
    public override async Task<bool> RunAsync(WorkflowActivityContext context, string expenseId)
    {
        if (string.IsNullOrWhiteSpace(expenseId))
        {
            throw new ArgumentException("ExpenseId is required.", nameof(expenseId));
        }

        var normalizedId = expenseId.Trim();
        var stateKey = RadiusClaimDapr.StateKeys.Expense(normalizedId);

        var record = await daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.PersistentStore,
            stateKey);

        if (record is null)
        {
            throw new InvalidOperationException(
                $"Expense '{normalizedId}' was not found in state store before recording approval.");
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
            LastUpdatedAtUtc = DateTimeOffset.UtcNow
        };

        await daprClient.SaveStateAsync(
            RadiusClaimDapr.Components.PersistentStore,
            stateKey,
            updatedRecord);

        logger.LogInformation(
            "Expense '{ExpenseId}' recorded as Approved (manual) for workflow '{InstanceId}'.",
            normalizedId,
            context.InstanceId);

        return true;
    }
}

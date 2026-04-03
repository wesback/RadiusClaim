using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Client;
using Dapr.Workflow;
using WorkflowEngine.Models;

namespace WorkflowEngine.Activities;

/// <summary>
/// Idempotent activity that transitions an expense from ManualReviewRequested → Rejected.
/// Used for both human-initiated rejections and automatic timeout rejections.
/// </summary>
internal sealed class RejectExpenseActivity(
    DaprClient daprClient,
    ILogger<RejectExpenseActivity> logger) : WorkflowActivity<RejectionInput, bool>
{
    public override async Task<bool> RunAsync(WorkflowActivityContext context, RejectionInput input)
    {
        ArgumentNullException.ThrowIfNull(input);

        if (string.IsNullOrWhiteSpace(input.ExpenseId))
        {
            throw new ArgumentException("ExpenseId is required.", nameof(input));
        }

        var stateKey = RadiusClaimDapr.StateKeys.Expense(input.ExpenseId);
        var record = await daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.PersistentStore,
            stateKey);

        if (record is null)
        {
            throw new InvalidOperationException(
                $"Expense '{input.ExpenseId}' was not found in state store before rejection.");
        }

        // Idempotent: already rejected is fine.
        if (record.Status == ExpenseStatus.Rejected)
        {
            logger.LogInformation(
                "Expense '{ExpenseId}' is already Rejected — skipping state update (idempotent) for workflow '{InstanceId}'.",
                input.ExpenseId,
                context.InstanceId);
            return true;
        }

        if (record.Status != ExpenseStatus.ManualReviewRequested)
        {
            throw new InvalidOperationException(
                $"Expense '{input.ExpenseId}' cannot be rejected from status '{record.Status}'. " +
                "Only ManualReviewRequested expenses can be rejected.");
        }

        var updatedRecord = record with
        {
            Status = ExpenseStatus.Rejected,
            RejectionReason = input.Reason,
            LastUpdatedAtUtc = DateTimeOffset.UtcNow
        };

        await daprClient.SaveStateAsync(
            RadiusClaimDapr.Components.PersistentStore,
            stateKey,
            updatedRecord);

        logger.LogInformation(
            "Expense '{ExpenseId}' rejected (reason: '{Reason}') for workflow '{InstanceId}'.",
            input.ExpenseId,
            input.Reason,
            context.InstanceId);

        return true;
    }
}

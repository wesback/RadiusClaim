using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Client;
using Dapr.Workflow;

namespace WorkflowEngine.Activities;

/// <summary>
/// Processes reimbursement for an approved expense.
/// Uses ConsistencyMode.Strong to ensure approved status is reliably visible
/// before reimbursement state is committed.
/// </summary>
internal sealed class ProcessReimbursementActivity(
    DaprClient daprClient,
    ILogger<ProcessReimbursementActivity> logger) : WorkflowActivity<string, bool>
{
    public override async Task<bool> RunAsync(WorkflowActivityContext context, string expenseId)
    {
        if (string.IsNullOrWhiteSpace(expenseId))
        {
            throw new ArgumentException("Expense id is required.", nameof(expenseId));
        }

        var normalizedExpenseId = expenseId.Trim();
        var stateKey = RadiusClaimDapr.StateKeys.Expense(normalizedExpenseId);
        var record = await daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.StateStore,
            stateKey,
            consistencyMode: ConsistencyMode.Strong);

        if (record is null)
        {
            throw new InvalidOperationException(
                $"Expense '{normalizedExpenseId}' was not found in state store before reimbursement.");
        }

        if (record.Status == ExpenseStatus.Reimbursed)
        {
            return true;
        }

        if (record.Status != ExpenseStatus.Approved)
        {
            throw new InvalidOperationException(
                $"Expense '{normalizedExpenseId}' cannot be reimbursed from status '{record.Status}'.");
        }

        var updatedRecord = record with
        {
            Status = ExpenseStatus.Reimbursed,
            LastUpdatedAtUtc = DateTimeOffset.UtcNow
        };

        await daprClient.SaveStateAsync(
            RadiusClaimDapr.Components.StateStore,
            stateKey,
            updatedRecord,
            stateOptions: new StateOptions { Consistency = ConsistencyMode.Strong });

        logger.LogInformation(
            "Expense '{ExpenseId}' was reimbursed for workflow '{InstanceId}'.",
            normalizedExpenseId,
            context.InstanceId);

        return true;
    }
}

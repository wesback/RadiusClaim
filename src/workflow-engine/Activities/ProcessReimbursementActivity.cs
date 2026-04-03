using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Client;
using Dapr.Workflow;

namespace WorkflowEngine.Activities;

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
            RadiusClaimDapr.Components.PersistentStore,
            stateKey);

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
            RadiusClaimDapr.Components.PersistentStore,
            stateKey,
            updatedRecord);

        logger.LogInformation(
            "Expense '{ExpenseId}' was reimbursed for workflow '{InstanceId}'.",
            normalizedExpenseId,
            context.InstanceId);

        return true;
    }
}

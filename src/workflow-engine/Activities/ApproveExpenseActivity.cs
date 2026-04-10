using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Client;
using Dapr.Workflow;
using Microsoft.Extensions.Options;
using WorkflowEngine.Models;

namespace WorkflowEngine.Activities;

/// <summary>
/// Evaluates expense approval eligibility and transitions state.
/// Uses ConsistencyMode.Strong to ensure consistent state visibility across replicas,
/// matching the pattern used in expense-api for reference consistency.
/// </summary>
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

        var threshold = approvalOptions.Value.ThresholdUsd;
        var isAutoApproved = input.Amount < threshold;
        var nextStatus = isAutoApproved ? ExpenseStatus.Approved : ExpenseStatus.ManualReviewRequested;
        var decision = new ApprovalDecision(
            nextStatus,
            isAutoApproved ? AutoApprovalDecisionSource : ManualReviewDecisionSource,
            isAutoApproved ? NotificationEventType.ExpenseApproved : NotificationEventType.ManualReviewRequested);

        var record = await daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.StateStore,
            RadiusClaimDapr.StateKeys.Expense(input.ExpenseId),
            consistencyMode: ConsistencyMode.Strong);

        // Cross-sidecar write-visibility race: expense-api may not yet have flushed the record
        // to the state store by the time this activity runs. The workflow input already carries
        // the authoritative amount, so we can route correctly without the persisted record.
        // We still write the bootstrapped record so the frontend sees the correct status.
        if (record is null)
        {
            logger.LogInformation(
                "Expense '{ExpenseId}' not yet visible in state store for workflow '{InstanceId}'. Routing from workflow input.",
                input.ExpenseId,
                context.InstanceId);

            var bootstrappedRecord = new ExpenseRecord(
                ExpenseId: input.ExpenseId,
                CorrelationId: input.CorrelationId,
                EmployeeId: input.EmployeeId,
                Amount: input.Amount,
                Currency: input.Currency,
                Description: input.Description,
                Status: nextStatus,
                SubmittedAtUtc: input.SubmittedAtUtc,
                LastUpdatedAtUtc: DateTimeOffset.UtcNow);

            await daprClient.SaveStateAsync(
                RadiusClaimDapr.Components.StateStore,
                RadiusClaimDapr.StateKeys.Expense(input.ExpenseId),
                bootstrappedRecord,
                stateOptions: new StateOptions { Consistency = ConsistencyMode.Strong });

            return decision;
        }

        if (!string.Equals(record.CorrelationId, input.CorrelationId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Expense '{input.ExpenseId}' correlation mismatch. Expected '{input.CorrelationId}', found '{record.CorrelationId}'.");
        }

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
            updatedRecord,
            stateOptions: new StateOptions { Consistency = ConsistencyMode.Strong });

        logger.LogInformation(
            "Expense '{ExpenseId}' moved to '{Status}' for workflow '{InstanceId}'.",
            input.ExpenseId,
            nextStatus,
            context.InstanceId);

        return decision;
    }
}

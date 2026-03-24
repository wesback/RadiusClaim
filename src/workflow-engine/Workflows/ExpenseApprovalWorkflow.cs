using RadiusClaim.Contracts;
using Dapr.Workflow;
using WorkflowEngine.Activities;
using WorkflowEngine.Models;

namespace WorkflowEngine.Workflows;

internal sealed class ExpenseApprovalWorkflow : Workflow<ExpenseSubmission, ExpenseApprovalWorkflowResult>
{
    public override async Task<ExpenseApprovalWorkflowResult> RunAsync(WorkflowContext context, ExpenseSubmission input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var decision = await context.CallActivityAsync<ApprovalDecision>(nameof(ApproveExpenseActivity), input);
        context.SetCustomStatus(new WorkflowProgress(
            input.ExpenseId,
            input.CorrelationId,
            decision.Status,
            "approval-recorded"));

        var finalStatus = decision.Status;
        if (decision.Status == ExpenseStatus.Approved)
        {
            await context.CallActivityAsync<bool>(nameof(ProcessReimbursementActivity), input.ExpenseId);
            finalStatus = ExpenseStatus.Reimbursed;

            context.SetCustomStatus(new WorkflowProgress(
                input.ExpenseId,
                input.CorrelationId,
                finalStatus,
                "reimbursement-recorded"));
        }

        var notification = BuildNotification(input, finalStatus, decision, context.CurrentUtcDateTime);
        await context.CallActivityAsync<bool>(nameof(PublishNotificationActivity), notification);

        context.SetCustomStatus(new WorkflowProgress(
            input.ExpenseId,
            input.CorrelationId,
            finalStatus,
            "notification-published"));

        return new ExpenseApprovalWorkflowResult(
            input.ExpenseId,
            input.CorrelationId,
            finalStatus,
            decision.NotificationEventType,
            decision.DecisionSource);
    }

    private static NotificationRequest BuildNotification(
        ExpenseSubmission input,
        ExpenseStatus finalStatus,
        ApprovalDecision decision,
        DateTime workflowUtcNow)
    {
        var occurredAtUtc = new DateTimeOffset(DateTime.SpecifyKind(workflowUtcNow, DateTimeKind.Utc));

        return decision.NotificationEventType switch
        {
            NotificationEventType.ExpenseApproved => new NotificationRequest(
                input.ExpenseId,
                input.CorrelationId,
                input.EmployeeId,
                "email",
                NotificationEventType.ExpenseApproved,
                $"Expense {input.ExpenseId} approved",
                $"Expense {input.ExpenseId} was auto-approved under $100.00 and is now {finalStatus}.",
                occurredAtUtc),
            NotificationEventType.ManualReviewRequested => new NotificationRequest(
                input.ExpenseId,
                input.CorrelationId,
                input.EmployeeId,
                "email",
                NotificationEventType.ManualReviewRequested,
                $"Expense {input.ExpenseId} needs manual review",
                $"Expense {input.ExpenseId} is ${input.Amount:F2} and was routed to manual review.",
                occurredAtUtc),
            _ => throw new InvalidOperationException(
                $"Unsupported notification event type '{decision.NotificationEventType}'.")
        };
    }
}

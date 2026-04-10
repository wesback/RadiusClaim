using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Workflow;
using Microsoft.Extensions.Options;
using WorkflowEngine.Activities;
using WorkflowEngine.Models;

namespace WorkflowEngine.Workflows;

internal sealed class ExpenseApprovalWorkflow(IOptions<ApprovalOptions> approvalOptions)
    : Workflow<ExpenseSubmission, ExpenseApprovalWorkflowResult>
{
    /// <summary>External event name raised by the approve/reject API endpoints.</summary>
    internal const string ManualDecisionEventName = RadiusClaimDapr.WorkflowEvents.ExpenseDecision;

    private const string ManualApprovalApprovedSource = "ManuallyApprovedByReviewer";
    private const string ManualApprovalRejectedSource = "ManuallyRejectedByReviewer";
    private const string ApprovalTimeoutRejectedSource = "AutoRejectedApprovalTimeout";

    public override async Task<ExpenseApprovalWorkflowResult> RunAsync(WorkflowContext context, ExpenseSubmission input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var decision = await context.CallActivityAsync<ApprovalDecision>(nameof(ApproveExpenseActivity), input);
        context.SetCustomStatus(new WorkflowProgress(
            input.ExpenseId,
            input.CorrelationId,
            decision.Status,
            "approval-recorded"));

        ExpenseStatus finalStatus;
        NotificationEventType finalEventType;
        string finalDecisionSource;

        if (decision.Status == ExpenseStatus.Approved)
        {
            // Fast path: auto-approved under threshold.
            await context.CallActivityAsync<bool>(nameof(ProcessReimbursementActivity), input.ExpenseId);
            finalStatus = ExpenseStatus.Reimbursed;
            finalEventType = NotificationEventType.ExpenseApproved;
            finalDecisionSource = decision.DecisionSource;

            context.SetCustomStatus(new WorkflowProgress(
                input.ExpenseId,
                input.CorrelationId,
                finalStatus,
                "reimbursement-recorded"));
        }
        else
        {
            // Human-in-the-loop path: notify approver, then pause and wait for a decision signal.
            var reviewNotification = BuildManualReviewNotification(input, context.CurrentUtcDateTime);
            await context.CallActivityAsync<bool>(nameof(PublishNotificationActivity), reviewNotification);

            context.SetCustomStatus(new WorkflowProgress(
                input.ExpenseId,
                input.CorrelationId,
                ExpenseStatus.ManualReviewRequested,
                "awaiting-manual-approval"));

            // Race: external decision event vs configurable timeout.
            var timeoutHours = approvalOptions.Value.ManualApprovalTimeoutHours;
            var decisionTask = context.WaitForExternalEventAsync<ManualDecisionEvent>(ManualDecisionEventName);
            var timeoutTask = context.CreateTimer(TimeSpan.FromHours(timeoutHours));
            var winner = await Task.WhenAny(decisionTask, timeoutTask);

            if (winner == decisionTask)
            {
                var manualDecision = await decisionTask;
                if (manualDecision?.Approved == true)
                {
                    // Transition ManualReviewRequested → Approved in state store before reimbursing.
                    await context.CallActivityAsync<bool>(nameof(RecordApprovalActivity), input.ExpenseId);

                    context.SetCustomStatus(new WorkflowProgress(
                        input.ExpenseId,
                        input.CorrelationId,
                        ExpenseStatus.Approved,
                        "manually-approved"));

                    await context.CallActivityAsync<bool>(nameof(ProcessReimbursementActivity), input.ExpenseId);
                    finalStatus = ExpenseStatus.Reimbursed;
                    finalEventType = NotificationEventType.ExpenseApproved;
                    finalDecisionSource = ManualApprovalApprovedSource;

                    context.SetCustomStatus(new WorkflowProgress(
                        input.ExpenseId,
                        input.CorrelationId,
                        finalStatus,
                        "reimbursement-recorded"));
                }
                else
                {
                    var reason = string.IsNullOrWhiteSpace(manualDecision?.Reason)
                        ? "Manual rejection by approver"
                        : manualDecision.Reason;

                    await context.CallActivityAsync<bool>(nameof(RejectExpenseActivity),
                        new RejectionInput(input.ExpenseId, input.CorrelationId, reason));

                    finalStatus = ExpenseStatus.Rejected;
                    finalEventType = NotificationEventType.ExpenseRejected;
                    finalDecisionSource = ManualApprovalRejectedSource;

                    context.SetCustomStatus(new WorkflowProgress(
                        input.ExpenseId,
                        input.CorrelationId,
                        finalStatus,
                        "rejection-recorded"));
                }
            }
            else
            {
                // Timeout expired — auto-reject.
                await context.CallActivityAsync<bool>(nameof(RejectExpenseActivity),
                    new RejectionInput(input.ExpenseId, input.CorrelationId, "Auto-rejected: approval timeout exceeded"));

                finalStatus = ExpenseStatus.Rejected;
                finalEventType = NotificationEventType.ExpenseRejected;
                finalDecisionSource = ApprovalTimeoutRejectedSource;

                context.SetCustomStatus(new WorkflowProgress(
                    input.ExpenseId,
                    input.CorrelationId,
                    finalStatus,
                    "rejection-recorded"));
            }
        }

        var notification = BuildFinalNotification(input, finalStatus, finalEventType, context.CurrentUtcDateTime);
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
            finalEventType,
            finalDecisionSource);
    }

    private static NotificationRequest BuildManualReviewNotification(
        ExpenseSubmission input,
        DateTime workflowUtcNow)
    {
        var occurredAtUtc = new DateTimeOffset(DateTime.SpecifyKind(workflowUtcNow, DateTimeKind.Utc));
        return new NotificationRequest(
            input.ExpenseId,
            input.CorrelationId,
            input.EmployeeId,
            "email",
            NotificationEventType.ManualReviewRequested,
            $"Expense {input.ExpenseId} needs manual review",
            $"Expense {input.ExpenseId} is ${input.Amount:F2} and requires approval. " +
            $"Use POST /expenses/{input.ExpenseId}/approve or /reject to decide.",
            occurredAtUtc);
    }

    private static NotificationRequest BuildFinalNotification(
        ExpenseSubmission input,
        ExpenseStatus finalStatus,
        NotificationEventType eventType,
        DateTime workflowUtcNow)
    {
        var occurredAtUtc = new DateTimeOffset(DateTime.SpecifyKind(workflowUtcNow, DateTimeKind.Utc));

        return eventType switch
        {
            NotificationEventType.ExpenseApproved => new NotificationRequest(
                input.ExpenseId,
                input.CorrelationId,
                input.EmployeeId,
                "email",
                NotificationEventType.ExpenseApproved,
                $"Expense {input.ExpenseId} approved",
                $"Expense {input.ExpenseId} was approved and is now {finalStatus}.",
                occurredAtUtc),
            NotificationEventType.ExpenseRejected => new NotificationRequest(
                input.ExpenseId,
                input.CorrelationId,
                input.EmployeeId,
                "email",
                NotificationEventType.ExpenseRejected,
                $"Expense {input.ExpenseId} rejected",
                $"Expense {input.ExpenseId} was rejected and is now {finalStatus}.",
                occurredAtUtc),
            _ => throw new InvalidOperationException(
                $"Unsupported final notification event type '{eventType}'.")
        };
    }
}


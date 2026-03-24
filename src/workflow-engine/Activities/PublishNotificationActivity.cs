using RadiusClaim.Contracts;
using Dapr.Client;
using Dapr.Workflow;

namespace WorkflowEngine.Activities;

internal sealed class PublishNotificationActivity(
    DaprClient daprClient,
    ILogger<PublishNotificationActivity> logger) : WorkflowActivity<NotificationRequest, bool>
{
    public override async Task<bool> RunAsync(WorkflowActivityContext context, NotificationRequest input)
    {
        ArgumentNullException.ThrowIfNull(input);

        await daprClient.PublishEventAsync(
            RadiusClaimDapr.Components.PubSub,
            RadiusClaimDapr.Topics.ExpenseNotifications,
            input);

        logger.LogInformation(
            "Published '{EventType}' notification for expense '{ExpenseId}' in workflow '{InstanceId}'.",
            input.EventType,
            input.ExpenseId,
            context.InstanceId);

        return true;
    }
}

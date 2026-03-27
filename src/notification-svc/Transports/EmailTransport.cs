using RadiusClaim.Contracts;

namespace NotificationSvc.Transports;

/// <summary>
/// Stubbed email transport.  In production this would construct and dispatch an SMTP message
/// (or call a SendGrid-style SDK).  The stub logs intent without opening a real connection,
/// making it safe to run in demo and CI environments without an SMTP relay.
/// </summary>
public sealed class EmailTransport(ILogger<EmailTransport> logger) : INotificationTransport
{
    public string TransportName => "email";

    public Task SendAsync(NotificationRequest notification, CancellationToken cancellationToken = default)
    {
        // TODO: replace with real SMTP/SendGrid call when relay is configured.
        logger.LogInformation(
            "NOTIFICATION_DELIVERED transport={Transport} to={Recipient} subject={Subject} eventType={EventType} expenseId={ExpenseId} correlationId={CorrelationId} channel={Channel} occurredAtUtc={OccurredAtUtc}",
            TransportName,
            notification.Recipient,
            notification.Subject,
            notification.EventType,
            notification.ExpenseId,
            notification.CorrelationId,
            notification.Channel,
            notification.OccurredAtUtc);

        return Task.CompletedTask;
    }
}

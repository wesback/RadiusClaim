using System.Text.Json;
using RadiusClaim.Contracts;

namespace NotificationSvc.Transports;

/// <summary>
/// Default transport: emits the notification as a structured JSON event to the application log.
/// Useful in demos and local development where no SMTP relay is configured.
/// </summary>
public sealed class LoggingTransport(ILogger<LoggingTransport> logger) : INotificationTransport
{
    public string TransportName => "log";

    public Task SendAsync(NotificationRequest notification, CancellationToken cancellationToken = default)
    {
        logger.LogInformation(
            "NOTIFICATION_DELIVERED transport={Transport} payload={Payload}",
            TransportName,
            JsonSerializer.Serialize(notification));

        return Task.CompletedTask;
    }
}

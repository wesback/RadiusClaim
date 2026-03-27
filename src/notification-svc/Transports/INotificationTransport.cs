using RadiusClaim.Contracts;

namespace NotificationSvc.Transports;

/// <summary>
/// Pluggable delivery channel for outbound notifications.
/// Selected at startup via the NOTIFICATION_TRANSPORT environment variable.
/// </summary>
public interface INotificationTransport
{
    /// <summary>Identifies the active transport for observability.</summary>
    string TransportName { get; }

    Task SendAsync(NotificationRequest notification, CancellationToken cancellationToken = default);
}

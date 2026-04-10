using Microsoft.Extensions.Logging.Abstractions;
using NotificationSvc.Transports;
using RadiusClaim.Contracts;
using Xunit;

namespace NotificationSvc.Tests.Transports;

public sealed class LoggingTransportTests
{
    private static NotificationRequest BuildNotification() => new(
        ExpenseId: "exp-1",
        CorrelationId: "corr-1",
        Recipient: "alice@example.com",
        Channel: "email",
        EventType: NotificationEventType.ExpenseApproved,
        Subject: "Expense approved",
        Message: "Your expense of $50 was approved.",
        OccurredAtUtc: DateTimeOffset.UtcNow);

    [Fact]
    public void TransportName_IsLog()
    {
        var transport = new LoggingTransport(NullLogger<LoggingTransport>.Instance);
        Assert.Equal("log", transport.TransportName);
    }

    [Fact]
    public async Task SendAsync_ValidNotification_CompletesSuccessfully()
    {
        var transport = new LoggingTransport(NullLogger<LoggingTransport>.Instance);
        // Should not throw
        await transport.SendAsync(BuildNotification());
    }

    [Fact]
    public async Task SendAsync_SupportsCancellation()
    {
        var transport = new LoggingTransport(NullLogger<LoggingTransport>.Instance);
        using var cts = new CancellationTokenSource();
        await transport.SendAsync(BuildNotification(), cts.Token);
    }
}

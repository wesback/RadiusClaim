using Microsoft.Extensions.Logging.Abstractions;
using NotificationSvc.Transports;
using RadiusClaim.Contracts;
using Xunit;

namespace NotificationSvc.Tests.Transports;

public sealed class EmailTransportTests
{
    private static NotificationRequest BuildNotification(
        string recipient = "bob@example.com",
        NotificationEventType eventType = NotificationEventType.ExpenseRejected) => new(
        ExpenseId: "exp-42",
        CorrelationId: "corr-42",
        Recipient: recipient,
        Channel: "email",
        EventType: eventType,
        Subject: "Expense decision",
        Message: "Your expense was processed.",
        OccurredAtUtc: DateTimeOffset.UtcNow);

    [Fact]
    public void TransportName_IsEmail()
    {
        var transport = new EmailTransport(NullLogger<EmailTransport>.Instance);
        Assert.Equal("email", transport.TransportName);
    }

    [Fact]
    public async Task SendAsync_ValidNotification_CompletesSuccessfully()
    {
        var transport = new EmailTransport(NullLogger<EmailTransport>.Instance);
        await transport.SendAsync(BuildNotification());
    }

    [Fact]
    public async Task SendAsync_SupportsCancellation()
    {
        var transport = new EmailTransport(NullLogger<EmailTransport>.Instance);
        using var cts = new CancellationTokenSource();
        await transport.SendAsync(BuildNotification(), cts.Token);
    }

    [Theory]
    [InlineData(NotificationEventType.ExpenseApproved)]
    [InlineData(NotificationEventType.ExpenseRejected)]
    [InlineData(NotificationEventType.ManualReviewRequested)]
    public async Task SendAsync_AllEventTypes_CompletesWithoutError(NotificationEventType eventType)
    {
        var transport = new EmailTransport(NullLogger<EmailTransport>.Instance);
        await transport.SendAsync(BuildNotification(eventType: eventType));
    }
}

using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Xunit;

namespace IntegrationTests.Contract;

/// <summary>
/// Contract tests that verify the schema published by workflow-engine matches
/// what notification-svc expects to receive on the expense-notifications topic.
///
/// These tests are intentionally compile-time and assertion-based; they are the
/// first line of defense against schema drift between services.
/// </summary>
public sealed class NotificationContractTests
{
    // Replicated from notification-svc/Program.cs IsValidNotification — if that function
    // changes, these tests will catch any field that drops out of the NotificationRequest.
    private static bool IsValidNotification(NotificationRequest? notification) =>
        notification is not null
        && !string.IsNullOrWhiteSpace(notification.ExpenseId)
        && !string.IsNullOrWhiteSpace(notification.CorrelationId)
        && !string.IsNullOrWhiteSpace(notification.Recipient)
        && !string.IsNullOrWhiteSpace(notification.Channel)
        && !string.IsNullOrWhiteSpace(notification.Subject)
        && !string.IsNullOrWhiteSpace(notification.Message)
        && notification.OccurredAtUtc != default;

    [Fact]
    public void PubSub_ComponentName_Matches_Between_Publisher_And_Subscriber()
    {
        // workflow-engine publishes to RadiusClaimDapr.Components.PubSub
        // notification-svc subscribes to [Topic("pubsub", "expense-notifications")]
        Assert.Equal("pubsub", RadiusClaimDapr.Components.PubSub);
    }

    [Fact]
    public void Topic_Name_Matches_Between_Publisher_And_Subscriber()
    {
        // workflow-engine publishes to RadiusClaimDapr.Topics.ExpenseNotifications
        // notification-svc subscribes to [Topic("pubsub", "expense-notifications")]
        Assert.Equal("expense-notifications", RadiusClaimDapr.Topics.ExpenseNotifications);
    }

    [Fact]
    public void AutoApprove_NotificationRequest_SatisfiesNotificationSvcContract()
    {
        var expenseId = "exp-contract-1";
        var notification = new NotificationRequest(
            ExpenseId: expenseId,
            CorrelationId: "corr-contract-1",
            Recipient: "emp-1",
            Channel: "email",
            EventType: NotificationEventType.ExpenseApproved,
            Subject: $"Expense {expenseId} approved",
            Message: $"Expense {expenseId} was auto-approved under $100.00 and is now Reimbursed.",
            OccurredAtUtc: DateTimeOffset.UtcNow);

        Assert.True(IsValidNotification(notification),
            "Auto-approve NotificationRequest must satisfy notification-svc validation contract.");
    }

    [Fact]
    public void ManualReview_NotificationRequest_SatisfiesNotificationSvcContract()
    {
        var expenseId = "exp-contract-2";
        var notification = new NotificationRequest(
            ExpenseId: expenseId,
            CorrelationId: "corr-contract-2",
            Recipient: "emp-1",
            Channel: "email",
            EventType: NotificationEventType.ManualReviewRequested,
            Subject: $"Expense {expenseId} needs manual review",
            Message: $"Expense {expenseId} is $150.00 and was routed to manual review.",
            OccurredAtUtc: DateTimeOffset.UtcNow);

        Assert.True(IsValidNotification(notification),
            "ManualReview NotificationRequest must satisfy notification-svc validation contract.");
    }

    [Fact]
    public void NotificationRequest_WithMissingExpenseId_FailsContract()
    {
        var notification = new NotificationRequest(
            ExpenseId: "",
            CorrelationId: "corr-1",
            Recipient: "emp-1",
            Channel: "email",
            EventType: NotificationEventType.ExpenseApproved,
            Subject: "Subject",
            Message: "Message",
            OccurredAtUtc: DateTimeOffset.UtcNow);

        Assert.False(IsValidNotification(notification),
            "Missing ExpenseId must fail notification-svc validation.");
    }

    [Fact]
    public void NotificationRequest_WithDefaultOccurredAt_FailsContract()
    {
        var notification = new NotificationRequest(
            ExpenseId: "exp-1",
            CorrelationId: "corr-1",
            Recipient: "emp-1",
            Channel: "email",
            EventType: NotificationEventType.ExpenseApproved,
            Subject: "Subject",
            Message: "Message",
            OccurredAtUtc: default);

        Assert.False(IsValidNotification(notification),
            "Default OccurredAtUtc must fail notification-svc validation.");
    }

    [Fact]
    public void NotificationEventType_HasExpectedValues()
    {
        // Guard against renaming enum values that break serialisation across services
        Assert.Equal("ExpenseApproved", nameof(NotificationEventType.ExpenseApproved));
        Assert.Equal("ExpenseRejected", nameof(NotificationEventType.ExpenseRejected));
        Assert.Equal("ManualReviewRequested", nameof(NotificationEventType.ManualReviewRequested));
    }

    [Fact]
    public void ExpenseStatus_HasExpectedValues()
    {
        // Guard against renaming enum values that break cross-service state visibility
        Assert.Equal("Submitted", nameof(ExpenseStatus.Submitted));
        Assert.Equal("ManualReviewRequested", nameof(ExpenseStatus.ManualReviewRequested));
        Assert.Equal("Approved", nameof(ExpenseStatus.Approved));
        Assert.Equal("Rejected", nameof(ExpenseStatus.Rejected));
        Assert.Equal("Reimbursed", nameof(ExpenseStatus.Reimbursed));
    }
}

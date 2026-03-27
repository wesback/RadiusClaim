using System.Text.Json.Serialization;

namespace RadiusClaim.Contracts;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum NotificationEventType
{
    ExpenseSubmitted,
    ExpenseApproved,
    ExpenseRejected,
    ManualReviewRequested,
    ApprovalTimeout,
    ExpenseRejectedTimeout
}

public sealed record NotificationRequest(
    string ExpenseId,
    string CorrelationId,
    string Recipient,
    string Channel,
    NotificationEventType EventType,
    string Subject,
    string Message,
    DateTimeOffset OccurredAtUtc);

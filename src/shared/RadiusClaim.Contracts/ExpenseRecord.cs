namespace RadiusClaim.Contracts;

public sealed record ExpenseRecord(
    string ExpenseId,
    string CorrelationId,
    string EmployeeId,
    decimal Amount,
    string Currency,
    string Description,
    ExpenseStatus Status,
    DateTimeOffset SubmittedAtUtc,
    DateTimeOffset LastUpdatedAtUtc,
    string? RejectionReason = null,
    /// <summary>Anonymous manual decisions leave this null; do not treat it as a verified reviewer identity.</summary>
    string? ApprovedBy = null,
    /// <summary>UTC timestamp when the workflow recorded the latest manual approval or rejection decision.</summary>
    DateTimeOffset? ApprovedAt = null);

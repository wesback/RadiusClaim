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
    /// <summary>Identity of the approver who acted on this expense (JWT sub/oid). Set on approval or rejection.</summary>
    string? ApprovedBy = null,
    /// <summary>UTC timestamp when the approval or rejection decision was recorded by the API.</summary>
    DateTimeOffset? ApprovedAt = null);

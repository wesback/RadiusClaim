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
    DateTimeOffset LastUpdatedAtUtc);

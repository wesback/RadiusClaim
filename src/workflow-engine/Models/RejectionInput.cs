namespace WorkflowEngine.Models;

internal sealed record RejectionInput(
    string ExpenseId,
    string CorrelationId,
    string Reason,
    DateTimeOffset DecisionTimeUtc);

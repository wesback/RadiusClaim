namespace WorkflowEngine.Models;

internal sealed record ApprovalRecordInput(
    string ExpenseId,
    string CorrelationId,
    DateTimeOffset DecisionTimeUtc);

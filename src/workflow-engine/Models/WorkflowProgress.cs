using RadiusClaim.Contracts;

namespace WorkflowEngine.Models;

internal sealed record WorkflowProgress(
    string ExpenseId,
    string CorrelationId,
    ExpenseStatus Status,
    string Step);

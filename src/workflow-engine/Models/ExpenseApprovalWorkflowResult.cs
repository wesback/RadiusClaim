using RadiusClaim.Contracts;

namespace WorkflowEngine.Models;

internal sealed record ExpenseApprovalWorkflowResult(
    string ExpenseId,
    string CorrelationId,
    ExpenseStatus FinalStatus,
    NotificationEventType NotificationEventType,
    string DecisionSource);

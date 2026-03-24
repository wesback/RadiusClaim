using RadiusClaim.Contracts;

namespace WorkflowEngine.Models;

internal sealed record ApprovalDecision(
    ExpenseStatus Status,
    string DecisionSource,
    NotificationEventType NotificationEventType);

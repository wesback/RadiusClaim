namespace WorkflowEngine.Models;

/// <summary>External event payload raised by the approve/reject API endpoints.</summary>
internal sealed record ManualDecisionEvent(
    bool Approved,
    string? Reason = null,
    DateTimeOffset DecisionTimeUtc = default);

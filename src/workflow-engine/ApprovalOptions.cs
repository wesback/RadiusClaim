namespace WorkflowEngine;

public sealed class ApprovalOptions
{
    public decimal ThresholdUsd { get; set; } = 100.0m;

    /// <summary>Hours before an unresolved manual-approval auto-rejects. Default: 48.</summary>
    public int ManualApprovalTimeoutHours { get; set; } = 48;
}

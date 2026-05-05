using Dapr;
using Dapr.Client;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using WorkflowEngine.Activities;
using WorkflowEngine.Models;
using WorkflowEngine.Tests.Helpers;
using Xunit;

namespace WorkflowEngine.Tests.Activities;

public sealed class RecordApprovalActivityTests
{
    private static readonly DateTimeOffset DecisionTimeUtc = new(2026, 05, 05, 12, 00, 00, TimeSpan.Zero);

    private static ApprovalRecordInput BuildInput(
        string correlationId = "corr-approve-1",
        DateTimeOffset? decisionTimeUtc = null) =>
        new(
            ExpenseId: "exp-approve-1",
            CorrelationId: correlationId,
            DecisionTimeUtc: decisionTimeUtc ?? DecisionTimeUtc);

    private static ExpenseRecord BuildRecord(
        ExpenseStatus status = ExpenseStatus.ManualReviewRequested,
        string correlationId = "corr-approve-1") =>
        new(
            ExpenseId: "exp-approve-1",
            CorrelationId: correlationId,
            EmployeeId: "emp-1",
            Amount: 250m,
            Currency: "USD",
            Description: "Test expense for approval",
            Status: status,
            SubmittedAtUtc: DateTimeOffset.UtcNow.AddHours(-1),
            LastUpdatedAtUtc: DateTimeOffset.UtcNow.AddMinutes(-5),
            RejectionReason: "Needs follow-up",
            ApprovedBy: "demo-reviewer",
            ApprovedAt: DateTimeOffset.UtcNow.AddMinutes(-10));

    private static Mock<DaprClient> BuildDaprMockReturning(ExpenseRecord? record)
    {
        var mock = new Mock<DaprClient>();
        mock.Setup(d => d.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(),
                It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(record);

        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(),
                It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        return mock;
    }

    [Fact]
    public async Task NullInput_ThrowsArgumentNullException()
    {
        var activity = new RecordApprovalActivity(
            BuildDaprMockReturning(null).Object,
            NullLogger<RecordApprovalActivity>.Instance);

        await Assert.ThrowsAsync<ArgumentNullException>(() =>
            activity.RunAsync(TestWorkflowContextFactory.Create(), null!));
    }

    [Fact]
    public async Task MissingStateRecord_ThrowsInvalidOperationException()
    {
        var activity = new RecordApprovalActivity(
            BuildDaprMockReturning(null).Object,
            NullLogger<RecordApprovalActivity>.Instance);

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput()));

        Assert.Contains("was not found in state store", ex.Message);
    }

    [Fact]
    public async Task CorrelationMismatch_ThrowsInvalidOperationException()
    {
        var activity = new RecordApprovalActivity(
            BuildDaprMockReturning(BuildRecord(correlationId: "different-corr")).Object,
            NullLogger<RecordApprovalActivity>.Instance);

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput()));

        Assert.Contains("correlation mismatch", ex.Message);
    }

    [Fact]
    public async Task ManualReviewRequested_TransitionsToApproved_AndClearsNonAuthoritativeAuditFields()
    {
        ExpenseRecord? savedRecord = null;
        var mock = BuildDaprMockReturning(BuildRecord());
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(),
                It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, _, value, _, _, _) => savedRecord = value)
            .Returns(Task.CompletedTask);

        var activity = new RecordApprovalActivity(mock.Object, NullLogger<RecordApprovalActivity>.Instance);
        var result = await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput());

        Assert.True(result);
        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.Approved, savedRecord!.Status);
        Assert.Null(savedRecord.RejectionReason);
        Assert.Null(savedRecord.ApprovedBy);
        Assert.Equal(DecisionTimeUtc, savedRecord.ApprovedAt);
        Assert.Equal(DecisionTimeUtc, savedRecord.LastUpdatedAtUtc);
    }

    [Theory]
    [InlineData(ExpenseStatus.Approved)]
    [InlineData(ExpenseStatus.Reimbursed)]
    public async Task ExistingApprovedStates_AreIdempotent_NoSaveStateCall(ExpenseStatus currentStatus)
    {
        var mock = BuildDaprMockReturning(BuildRecord(currentStatus));
        var activity = new RecordApprovalActivity(mock.Object, NullLogger<RecordApprovalActivity>.Instance);

        var result = await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput());

        Assert.True(result);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(),
            It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task SavesTo_CorrectStateStoreKey()
    {
        string? usedStateKey = null;
        var mock = BuildDaprMockReturning(BuildRecord());
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(),
                It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, key, _, _, _, _) => usedStateKey = key)
            .Returns(Task.CompletedTask);

        var activity = new RecordApprovalActivity(mock.Object, NullLogger<RecordApprovalActivity>.Instance);
        await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput());

        Assert.Equal(RadiusClaimDapr.StateKeys.Expense("exp-approve-1"), usedStateKey);
    }
}

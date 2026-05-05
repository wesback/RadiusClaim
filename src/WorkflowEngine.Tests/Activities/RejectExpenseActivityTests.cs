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

public sealed class RejectExpenseActivityTests
{
    private static readonly DateTimeOffset DecisionTimeUtc = new(2026, 05, 05, 13, 30, 00, TimeSpan.Zero);

    private static RejectionInput BuildInput(
        string reason = "Manual rejection by approver",
        string correlationId = "corr-reject-1",
        DateTimeOffset? decisionTimeUtc = null) =>
        new(
            ExpenseId: "exp-reject-1",
            CorrelationId: correlationId,
            Reason: reason,
            DecisionTimeUtc: decisionTimeUtc ?? DecisionTimeUtc);

    private static ExpenseRecord BuildRecord(
        ExpenseStatus status = ExpenseStatus.ManualReviewRequested,
        string correlationId = "corr-reject-1") =>
        new(
            ExpenseId: "exp-reject-1",
            CorrelationId: correlationId,
            EmployeeId: "emp-1",
            Amount: 250m,
            Currency: "USD",
            Description: "Test expense for rejection",
            Status: status,
            SubmittedAtUtc: DateTimeOffset.UtcNow,
            LastUpdatedAtUtc: DateTimeOffset.UtcNow,
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
        var mock = BuildDaprMockReturning(null);
        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        await Assert.ThrowsAsync<ArgumentNullException>(() => activity.RunAsync(ctx, null!));
    }

    [Fact]
    public async Task MissingStateRecord_ThrowsInvalidOperationException()
    {
        var mock = BuildDaprMockReturning(null);
        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, BuildInput()));

        Assert.Contains("was not found in state store", ex.Message);
    }

    [Fact]
    public async Task AlreadyRejected_IsIdempotent_NoSaveStateCall()
    {
        var record = BuildRecord(ExpenseStatus.Rejected);
        var mock = BuildDaprMockReturning(record);
        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var result = await activity.RunAsync(ctx, BuildInput());

        Assert.True(result);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task CorrelationMismatch_ThrowsInvalidOperationException()
    {
        var mock = BuildDaprMockReturning(BuildRecord(correlationId: "different-corr"));
        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, BuildInput()));

        Assert.Contains("correlation mismatch", ex.Message);
    }

    [Theory]
    [InlineData(ExpenseStatus.Submitted)]
    [InlineData(ExpenseStatus.Approved)]
    [InlineData(ExpenseStatus.Reimbursed)]
    public async Task InvalidStateTransition_ThrowsInvalidOperationException(ExpenseStatus currentStatus)
    {
        var record = BuildRecord(currentStatus);
        var mock = BuildDaprMockReturning(record);
        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, BuildInput()));

        Assert.Contains("cannot be rejected from status", ex.Message);
        Assert.Contains(currentStatus.ToString(), ex.Message);
    }

    [Fact]
    public async Task ManualReviewRequested_TransitionsToRejected_SavesState()
    {
        var record = BuildRecord(ExpenseStatus.ManualReviewRequested);
        ExpenseRecord? savedRecord = null;
        var mock = new Mock<DaprClient>();
        mock.Setup(d => d.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(record);
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, _, value, _, _, _) => savedRecord = value)
            .Returns(Task.CompletedTask);

        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        var result = await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput());

        Assert.True(result);
        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.Rejected, savedRecord!.Status);
        Assert.Null(savedRecord.ApprovedBy);
        Assert.Equal(DecisionTimeUtc, savedRecord.ApprovedAt);
        Assert.Equal(DecisionTimeUtc, savedRecord.LastUpdatedAtUtc);
    }

    [Fact]
    public async Task ManualReview_CapturesRejectionReason_InStateRecord()
    {
        const string reason = "Amount exceeds policy limit for this cost centre";
        var record = BuildRecord(ExpenseStatus.ManualReviewRequested);
        ExpenseRecord? savedRecord = null;
        var mock = new Mock<DaprClient>();
        mock.Setup(d => d.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(record);
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, _, value, _, _, _) => savedRecord = value)
            .Returns(Task.CompletedTask);

        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput(reason));

        Assert.Equal(reason, savedRecord!.RejectionReason);
        Assert.Null(savedRecord.ApprovedBy);
        Assert.Equal(DecisionTimeUtc, savedRecord.ApprovedAt);
    }

    [Fact]
    public async Task AutoRejectionTimeout_CapturesTimeoutReason()
    {
        const string timeoutReason = "Auto-rejected: approval timeout exceeded";
        var record = BuildRecord(ExpenseStatus.ManualReviewRequested);
        ExpenseRecord? savedRecord = null;
        var mock = new Mock<DaprClient>();
        mock.Setup(d => d.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(record);
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, _, value, _, _, _) => savedRecord = value)
            .Returns(Task.CompletedTask);

        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput(timeoutReason));

        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.Rejected, savedRecord!.Status);
        Assert.Equal(timeoutReason, savedRecord.RejectionReason);
        Assert.Equal(DecisionTimeUtc, savedRecord.ApprovedAt);
    }

    [Fact]
    public async Task SavesTo_CorrectStateStoreKey()
    {
        var record = BuildRecord(ExpenseStatus.ManualReviewRequested);
        string? usedStateKey = null;
        var mock = new Mock<DaprClient>();
        mock.Setup(d => d.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(record);
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, key, _, _, _, _) => usedStateKey = key)
            .Returns(Task.CompletedTask);

        var activity = new RejectExpenseActivity(mock.Object, NullLogger<RejectExpenseActivity>.Instance);
        await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildInput());

        Assert.Equal(RadiusClaimDapr.StateKeys.Expense("exp-reject-1"), usedStateKey);
    }
}

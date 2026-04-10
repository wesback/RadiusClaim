using Dapr;
using Dapr.Client;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using RadiusClaim.Contracts;
using WorkflowEngine;
using WorkflowEngine.Activities;
using WorkflowEngine.Tests.Helpers;
using Xunit;

namespace WorkflowEngine.Tests.Activities;

public sealed class ApproveExpenseActivityTests
{
    private static IOptions<ApprovalOptions> DefaultOptions() =>
        Options.Create(new ApprovalOptions());

    private static IOptions<ApprovalOptions> OptionsWithThreshold(decimal threshold) =>
        Options.Create(new ApprovalOptions { ThresholdUsd = threshold });

    private static ExpenseSubmission BuildSubmission(decimal amount) =>
        new(
            ExpenseId: "exp-1",
            CorrelationId: "corr-1",
            EmployeeId: "emp-1",
            Amount: amount,
            Currency: "USD",
            Description: "Test expense",
            SubmittedAtUtc: DateTimeOffset.UtcNow);

    private static ExpenseRecord BuildRecord(decimal amount, ExpenseStatus status = ExpenseStatus.Submitted) =>
        new(
            ExpenseId: "exp-1",
            CorrelationId: "corr-1",
            EmployeeId: "emp-1",
            Amount: amount,
            Currency: "USD",
            Description: "Test expense",
            Status: status,
            SubmittedAtUtc: DateTimeOffset.UtcNow,
            LastUpdatedAtUtc: DateTimeOffset.UtcNow);

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

    // -- Default threshold (100.00) tests ------------------------------------

    [Theory]
    [InlineData(0.01)]
    [InlineData(50)]
    [InlineData(99.99)]
    public async Task Amount_UnderThreshold_AutoApproves(decimal amount)
    {
        var record = BuildRecord(amount);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(amount));

        Assert.Equal(ExpenseStatus.Approved, decision.Status);
        Assert.Equal("AutoApprovedUnderThreshold", decision.DecisionSource);
        Assert.Equal(NotificationEventType.ExpenseApproved, decision.NotificationEventType);
    }

    [Theory]
    [InlineData(100.00)]
    [InlineData(100.01)]
    [InlineData(500)]
    public async Task Amount_AtOrAboveThreshold_RequiresManualReview(decimal amount)
    {
        var record = BuildRecord(amount);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(amount));

        Assert.Equal(ExpenseStatus.ManualReviewRequested, decision.Status);
        Assert.Equal("ManualReviewThresholdReached", decision.DecisionSource);
        Assert.Equal(NotificationEventType.ManualReviewRequested, decision.NotificationEventType);
    }

    // -- Configurable threshold tests ----------------------------------------

    [Theory]
    [InlineData(250.00, 249.99, "Approved")]
    [InlineData(250.00, 250.00, "ManualReviewRequested")]
    [InlineData(250.00, 300.00, "ManualReviewRequested")]
    [InlineData(50.00, 49.99, "Approved")]
    [InlineData(50.00, 50.00, "ManualReviewRequested")]
    public async Task CustomThreshold_RoutesCorrectly(decimal threshold, decimal amount, string expectedStatusStr)
    {
        var expectedStatus = Enum.Parse<ExpenseStatus>(expectedStatusStr);
        var record = BuildRecord(amount);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, OptionsWithThreshold(threshold), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(amount));

        Assert.Equal(expectedStatus, decision.Status);
    }

    [Fact]
    public async Task ThresholdBoundary_ExactlyAtThreshold_IsManualReview()
    {
        var threshold = 100.00m;
        var record = BuildRecord(threshold);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(threshold));

        Assert.Equal(ExpenseStatus.ManualReviewRequested, decision.Status);
    }

    [Fact]
    public async Task ThresholdBoundary_JustUnderThreshold_IsAutoApproved()
    {
        var amount = 99.99m;
        var record = BuildRecord(amount);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(amount));

        Assert.Equal(ExpenseStatus.Approved, decision.Status);
    }

    // -- Error cases ---------------------------------------------------------

    [Fact]
    public async Task NullInput_ThrowsArgumentNullException()
    {
        var mock = BuildDaprMockReturning(null);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        await Assert.ThrowsAsync<ArgumentNullException>(() => activity.RunAsync(ctx, null!));
    }

    [Fact]
    public async Task MissingStateRecord_UnderThreshold_ReturnsAutoApproveFromInput()
    {
        // Cross-sidecar race: record not yet visible. Decision must come from workflow input.
        // A bootstrapped record with Approved status must be written so downstream activities
        // find a consistent state even if expense-api hasn't flushed yet.
        ExpenseRecord? savedRecord = null;
        var mock = BuildDaprMockReturning(null);
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, _, value, _, _, _) => savedRecord = value)
            .Returns(Task.CompletedTask);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(50m));

        Assert.Equal(ExpenseStatus.Approved, decision.Status);
        Assert.Equal("AutoApprovedUnderThreshold", decision.DecisionSource);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Once);
        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.Approved, savedRecord!.Status);
    }

    [Fact]
    public async Task MissingStateRecord_AtThreshold_ReturnsManualReviewFromInput()
    {
        // Cross-sidecar race: record not yet visible. A bootstrapped record with
        // ManualReviewRequested status must be written so the frontend approval button renders.
        ExpenseRecord? savedRecord = null;
        var mock = BuildDaprMockReturning(null);
        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, _, value, _, _, _) => savedRecord = value)
            .Returns(Task.CompletedTask);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(100m));

        Assert.Equal(ExpenseStatus.ManualReviewRequested, decision.Status);
        Assert.Equal("ManualReviewThresholdReached", decision.DecisionSource);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Once);
        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.ManualReviewRequested, savedRecord!.Status);
    }

    [Fact]
    public async Task CorrelationMismatch_ThrowsInvalidOperationException()
    {
        var record = BuildRecord(50m) with { CorrelationId = "different-corr" };
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, BuildSubmission(50m)));

        Assert.Contains("correlation mismatch", ex.Message);
    }

    [Theory]
    [InlineData(ExpenseStatus.ManualReviewRequested)]
    [InlineData(ExpenseStatus.Rejected)]
    public async Task InvalidStateTransition_ThrowsInvalidOperationException(ExpenseStatus currentStatus)
    {
        var record = BuildRecord(50m, currentStatus);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, BuildSubmission(50m)));

        Assert.Contains("cannot transition", ex.Message);
    }

    // -- Idempotency tests ---------------------------------------------------

    [Fact]
    public async Task AlreadyApproved_Status_IsIdempotent()
    {
        // A record already at Approved status should return the AutoApprove decision without re-saving
        var record = BuildRecord(50m, ExpenseStatus.Approved);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(50m));

        Assert.Equal(ExpenseStatus.Approved, decision.Status);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task AlreadyReimbursed_AutoApprove_IsIdempotent()
    {
        // If already reimbursed (completed auto-approve path), return decision without modifying state
        var record = BuildRecord(50m, ExpenseStatus.Reimbursed);
        var mock = BuildDaprMockReturning(record);
        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var decision = await activity.RunAsync(ctx, BuildSubmission(50m));

        Assert.Equal(ExpenseStatus.Approved, decision.Status);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    // -- State store persistence tests ---------------------------------------

    [Fact]
    public async Task AutoApprove_SavesApprovedStatusToStateStore()
    {
        var record = BuildRecord(50m);
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

        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildSubmission(50m));

        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.Approved, savedRecord!.Status);
    }

    [Fact]
    public async Task ManualReview_SavesManualReviewStatusToStateStore()
    {
        var record = BuildRecord(150m);
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

        var activity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        await activity.RunAsync(TestWorkflowContextFactory.Create(), BuildSubmission(150m));

        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.ManualReviewRequested, savedRecord!.Status);
    }
}

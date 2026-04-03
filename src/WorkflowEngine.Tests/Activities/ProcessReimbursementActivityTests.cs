using Dapr;
using Dapr.Client;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using RadiusClaim.Contracts;
using WorkflowEngine.Activities;
using WorkflowEngine.Tests.Helpers;
using Xunit;

namespace WorkflowEngine.Tests.Activities;

public sealed class ProcessReimbursementActivityTests
{
    private static ExpenseRecord BuildRecord(ExpenseStatus status) =>
        new(
            ExpenseId: "exp-2",
            CorrelationId: "corr-2",
            EmployeeId: "emp-1",
            Amount: 50m,
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

    [Fact]
    public async Task ApprovedExpense_TransitionsToReimbursed_ReturnsTrue()
    {
        var record = BuildRecord(ExpenseStatus.Approved);
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

        var activity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var result = await activity.RunAsync(ctx, "exp-2");

        Assert.True(result);
        Assert.NotNull(savedRecord);
        Assert.Equal(ExpenseStatus.Reimbursed, savedRecord!.Status);
    }

    [Fact]
    public async Task AlreadyReimbursed_IsIdempotent_ReturnsTrueWithoutSaving()
    {
        var record = BuildRecord(ExpenseStatus.Reimbursed);
        var mock = BuildDaprMockReturning(record);
        var activity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var result = await activity.RunAsync(ctx, "exp-2");

        Assert.True(result);
        mock.Verify(d => d.SaveStateAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
            It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    [Theory]
    [InlineData(ExpenseStatus.Submitted)]
    [InlineData(ExpenseStatus.ManualReviewRequested)]
    [InlineData(ExpenseStatus.Rejected)]
    public async Task NonApprovedStatus_ThrowsInvalidOperationException(ExpenseStatus status)
    {
        var record = BuildRecord(status);
        var mock = BuildDaprMockReturning(record);
        var activity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, "exp-2"));

        Assert.Contains("cannot be reimbursed from status", ex.Message);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task EmptyOrWhitespaceExpenseId_ThrowsArgumentException(string expenseId)
    {
        var mock = BuildDaprMockReturning(null);
        var activity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        await Assert.ThrowsAsync<ArgumentException>(() => activity.RunAsync(ctx, expenseId));
    }

    [Fact]
    public async Task MissingRecord_ThrowsInvalidOperationException()
    {
        var mock = BuildDaprMockReturning(null);
        var activity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => activity.RunAsync(ctx, "exp-2"));

        Assert.Contains("was not found in state store", ex.Message);
    }

    [Fact]
    public async Task ExpenseIdWithWhitespace_IsNormalized()
    {
        var record = BuildRecord(ExpenseStatus.Approved);
        var mock = BuildDaprMockReturning(record);
        var activity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var ctx = TestWorkflowContextFactory.Create();

        // Should succeed — leading/trailing whitespace is trimmed before lookup
        var result = await activity.RunAsync(ctx, "  exp-2  ");

        Assert.True(result);
    }
}

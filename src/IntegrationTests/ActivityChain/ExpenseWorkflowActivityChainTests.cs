using Dapr;
using Dapr.Client;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Workflow;
using WorkflowEngine;
using WorkflowEngine.Activities;
using Xunit;

namespace IntegrationTests.ActivityChain;

/// <summary>
/// End-to-end activity chain tests. These drive the three workflow activities in sequence
/// using an in-memory Dapr state store fake, verifying the full submit → approve → notify
/// flow without requiring a running Dapr sidecar.
/// </summary>
public sealed class ExpenseWorkflowActivityChainTests
{
    private static IOptions<ApprovalOptions> DefaultOptions() =>
        Options.Create(new ApprovalOptions { ThresholdUsd = 100m });

    private static WorkflowActivityContext CreateContext(string instanceId = "test-workflow")
    {
        var mock = new Mock<WorkflowActivityContext>();
        mock.Setup(c => c.InstanceId).Returns(instanceId);
        return mock.Object;
    }

    private static (Mock<DaprClient> mock, Dictionary<string, ExpenseRecord> stateStore, List<NotificationRequest> published)
        BuildInMemoryDapr(ExpenseRecord initialRecord)
    {
        var stateStore = new Dictionary<string, ExpenseRecord>
        {
            [RadiusClaimDapr.StateKeys.Expense(initialRecord.ExpenseId)] = initialRecord
        };
        var published = new List<NotificationRequest>();

        var mock = new Mock<DaprClient>();

        mock.Setup(d => d.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync((string _, string key, ConsistencyMode? _, IReadOnlyDictionary<string, string>? _, CancellationToken _) =>
                stateStore.TryGetValue(key, out var r) ? r : null);

        mock.Setup(d => d.SaveStateAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(), It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, ExpenseRecord, StateOptions?, IReadOnlyDictionary<string, string>?, CancellationToken>(
                (_, key, value, _, _, _) => stateStore[key] = value)
            .Returns(Task.CompletedTask);

        mock.Setup(d => d.PublishEventAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<NotificationRequest>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, NotificationRequest, CancellationToken>(
                (_, _, notification, _) => published.Add(notification))
            .Returns(Task.CompletedTask);

        return (mock, stateStore, published);
    }

    private static ExpenseRecord MakeRecord(string expenseId, string correlationId, decimal amount) =>
        new(
            ExpenseId: expenseId,
            CorrelationId: correlationId,
            EmployeeId: "emp-integration",
            Amount: amount,
            Currency: "USD",
            Description: "Integration test expense",
            Status: ExpenseStatus.Submitted,
            SubmittedAtUtc: DateTimeOffset.UtcNow,
            LastUpdatedAtUtc: DateTimeOffset.UtcNow);

    private static ExpenseSubmission MakeSubmission(string expenseId, string correlationId, decimal amount) =>
        new(
            ExpenseId: expenseId,
            CorrelationId: correlationId,
            EmployeeId: "emp-integration",
            Amount: amount,
            Currency: "USD",
            Description: "Integration test expense",
            SubmittedAtUtc: DateTimeOffset.UtcNow);

    [Fact]
    public async Task AutoApprove_Path_FullChain_ApprovesThenReimbursesThenNotifies()
    {
        const string expenseId = "exp-auto-chain";
        const string correlationId = "corr-auto-chain";
        var record = MakeRecord(expenseId, correlationId, 49.99m);
        var submission = MakeSubmission(expenseId, correlationId, 49.99m);
        var (mock, stateStore, published) = BuildInMemoryDapr(record);
        var ctx = CreateContext("workflow-auto-chain");

        // Step 1: Approve
        var approveActivity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var decision = await approveActivity.RunAsync(ctx, submission);

        Assert.Equal(ExpenseStatus.Approved, decision.Status);
        Assert.Equal(ExpenseStatus.Approved, stateStore[RadiusClaimDapr.StateKeys.Expense(expenseId)].Status);

        // Step 2: Reimburse (auto-approve branch triggers this)
        var reimburseActivity = new ProcessReimbursementActivity(mock.Object, NullLogger<ProcessReimbursementActivity>.Instance);
        var reimbursed = await reimburseActivity.RunAsync(ctx, expenseId);

        Assert.True(reimbursed);
        Assert.Equal(ExpenseStatus.Reimbursed, stateStore[RadiusClaimDapr.StateKeys.Expense(expenseId)].Status);

        // Step 3: Publish notification
        var notification = new NotificationRequest(
            expenseId, correlationId, "emp-integration", "email",
            NotificationEventType.ExpenseApproved,
            $"Expense {expenseId} approved",
            $"Expense {expenseId} was auto-approved under $100.00 and is now {ExpenseStatus.Reimbursed}.",
            DateTimeOffset.UtcNow);

        var notifyActivity = new PublishNotificationActivity(mock.Object, NullLogger<PublishNotificationActivity>.Instance);
        await notifyActivity.RunAsync(ctx, notification);

        Assert.Single(published);
        Assert.Equal(NotificationEventType.ExpenseApproved, published[0].EventType);
        Assert.Equal(expenseId, published[0].ExpenseId);
        mock.Verify(d => d.PublishEventAsync(
            RadiusClaimDapr.Components.PubSub,
            RadiusClaimDapr.Topics.ExpenseNotifications,
            It.IsAny<NotificationRequest>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ManualReview_Path_FullChain_RoutesToReviewAndNotifies_WithoutReimbursing()
    {
        const string expenseId = "exp-manual-chain";
        const string correlationId = "corr-manual-chain";
        var record = MakeRecord(expenseId, correlationId, 250m);
        var submission = MakeSubmission(expenseId, correlationId, 250m);
        var (mock, stateStore, published) = BuildInMemoryDapr(record);
        var ctx = CreateContext("workflow-manual-chain");

        // Step 1: Approve — routes to manual review
        var approveActivity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var decision = await approveActivity.RunAsync(ctx, submission);

        Assert.Equal(ExpenseStatus.ManualReviewRequested, decision.Status);
        Assert.Equal(ExpenseStatus.ManualReviewRequested, stateStore[RadiusClaimDapr.StateKeys.Expense(expenseId)].Status);

        // Step 2: ProcessReimbursementActivity is NOT called for manual review path
        // (this is the workflow branching guard — the next step is notification only)

        // Step 3: Publish manual review notification
        var notification = new NotificationRequest(
            expenseId, correlationId, "emp-integration", "email",
            NotificationEventType.ManualReviewRequested,
            $"Expense {expenseId} needs manual review",
            $"Expense {expenseId} is $250.00 and was routed to manual review.",
            DateTimeOffset.UtcNow);

        var notifyActivity = new PublishNotificationActivity(mock.Object, NullLogger<PublishNotificationActivity>.Instance);
        await notifyActivity.RunAsync(ctx, notification);

        Assert.Single(published);
        Assert.Equal(NotificationEventType.ManualReviewRequested, published[0].EventType);
        Assert.Equal(expenseId, published[0].ExpenseId);

        // Guard: reimburse activity was never called — state stays at ManualReviewRequested
        Assert.Equal(ExpenseStatus.ManualReviewRequested, stateStore[RadiusClaimDapr.StateKeys.Expense(expenseId)].Status);
    }

    [Fact]
    public async Task BoundaryAmount_ExactlyOneHundred_RoutesToManualReview()
    {
        const string expenseId = "exp-boundary";
        const string correlationId = "corr-boundary";
        var record = MakeRecord(expenseId, correlationId, 100.00m);
        var submission = MakeSubmission(expenseId, correlationId, 100.00m);
        var (mock, stateStore, _) = BuildInMemoryDapr(record);
        var ctx = CreateContext("workflow-boundary");

        var approveActivity = new ApproveExpenseActivity(mock.Object, DefaultOptions(), NullLogger<ApproveExpenseActivity>.Instance);
        var decision = await approveActivity.RunAsync(ctx, submission);

        Assert.Equal(ExpenseStatus.ManualReviewRequested, decision.Status);
        Assert.Equal(ExpenseStatus.ManualReviewRequested, stateStore[RadiusClaimDapr.StateKeys.Expense(expenseId)].Status);
    }

    [Fact]
    public async Task Notification_PublishedTo_CorrectPubSubAndTopic()
    {
        const string expenseId = "exp-topic-check";
        const string correlationId = "corr-topic-check";
        var record = MakeRecord(expenseId, correlationId, 75m);
        var (mock, _, _) = BuildInMemoryDapr(record);
        var ctx = CreateContext("workflow-topic-check");

        var notification = new NotificationRequest(
            expenseId, correlationId, "emp-integration", "email",
            NotificationEventType.ExpenseApproved,
            "Subject", "Message", DateTimeOffset.UtcNow);

        var notifyActivity = new PublishNotificationActivity(mock.Object, NullLogger<PublishNotificationActivity>.Instance);
        await notifyActivity.RunAsync(ctx, notification);

        mock.Verify(d => d.PublishEventAsync(
            RadiusClaimDapr.Components.PubSub,        // "pubsub"
            RadiusClaimDapr.Topics.ExpenseNotifications, // "expense-notifications"
            It.IsAny<NotificationRequest>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }
}

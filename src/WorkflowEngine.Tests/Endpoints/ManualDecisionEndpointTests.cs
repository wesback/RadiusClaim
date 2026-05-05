using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.Extensions.Logging.Abstractions;
using WorkflowEngine.Models;
using Xunit;

namespace WorkflowEngine.Tests.Endpoints;

public sealed class ManualDecisionEndpointTests
{
    [Fact]
    public async Task AnonymousApprovalDecision_DoesNotRequireApiToken()
    {
        var client = new FakeWorkflowDecisionClient(new WorkflowDecisionState(true, true, "Running"));
        var httpContext = CreateHttpContext();

        var result = await Program.HandleManualDecisionAsync(
            "wf-approve-1",
            httpContext,
            new ManualDecisionRequest(true),
            client,
            NullLogger<Program>.Instance,
            CancellationToken.None);

        var accepted = Assert.IsType<Accepted<WorkflowDecisionAcceptedResponse>>(result);

        var acceptedValue = Assert.IsType<WorkflowDecisionAcceptedResponse>(accepted.Value);

        Assert.Equal(StatusCodes.Status202Accepted, accepted.StatusCode);
        Assert.Equal("/workflows/wf-approve-1", accepted.Location);
        Assert.Equal("wf-approve-1", acceptedValue.InstanceId);
        Assert.Equal("Approved", acceptedValue.Decision);
        var raisedEvent = Assert.Single(client.RaisedEvents);
        Assert.Equal("wf-approve-1", raisedEvent.InstanceId);
        Assert.True(raisedEvent.DecisionEvent.Approved);
        Assert.Null(raisedEvent.DecisionEvent.Reason);
    }

    [Fact]
    public async Task AnonymousRejectionDecision_UsesDefaultReasonWithoutApiToken()
    {
        var client = new FakeWorkflowDecisionClient(new WorkflowDecisionState(true, true, "Running"));
        var httpContext = CreateHttpContext();

        var result = await Program.HandleManualDecisionAsync(
            "wf-reject-1",
            httpContext,
            new ManualDecisionRequest(false),
            client,
            NullLogger<Program>.Instance,
            CancellationToken.None);

        var accepted = Assert.IsType<Accepted<WorkflowDecisionAcceptedResponse>>(result);

        _ = Assert.IsType<WorkflowDecisionAcceptedResponse>(accepted.Value);

        Assert.Equal(StatusCodes.Status202Accepted, accepted.StatusCode);
        var raisedEvent = Assert.Single(client.RaisedEvents);
        Assert.False(raisedEvent.DecisionEvent.Approved);
        Assert.Equal("Manual rejection by approver", raisedEvent.DecisionEvent.Reason);
    }

    [Fact]
    public async Task MissingWorkflow_ReturnsNotFound()
    {
        var client = new FakeWorkflowDecisionClient(new WorkflowDecisionState(false, false, null));
        var httpContext = CreateHttpContext();

        var result = await Program.HandleManualDecisionAsync(
            "wf-missing",
            httpContext,
            new ManualDecisionRequest(true),
            client,
            NullLogger<Program>.Instance,
            CancellationToken.None);

        var notFound = Assert.IsType<NotFound>(result);

        Assert.Equal(StatusCodes.Status404NotFound, notFound.StatusCode);
        Assert.Empty(client.RaisedEvents);
    }

    [Fact]
    public async Task NonRunningWorkflow_ReturnsConflictWithRuntimeStatus()
    {
        var client = new FakeWorkflowDecisionClient(new WorkflowDecisionState(true, false, "Completed"));
        var httpContext = CreateHttpContext();

        var result = await Program.HandleManualDecisionAsync(
            "wf-complete",
            httpContext,
            new ManualDecisionRequest(true),
            client,
            NullLogger<Program>.Instance,
            CancellationToken.None);

        var conflict = Assert.IsType<Conflict<WorkflowDecisionConflictResponse>>(result);

        var conflictValue = Assert.IsType<WorkflowDecisionConflictResponse>(conflict.Value);

        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Equal("Workflow is not running and cannot accept a decision.", conflictValue.Error);
        Assert.Equal("wf-complete", conflictValue.InstanceId);
        Assert.Equal("Completed", conflictValue.RuntimeStatus);
        Assert.Empty(client.RaisedEvents);
    }

    [Fact]
    public async Task RaiseFailure_ReturnsProblemDetails()
    {
        var client = new FakeWorkflowDecisionClient(new WorkflowDecisionState(true, true, "Running"))
        {
            RaiseException = new InvalidOperationException("sidecar unavailable")
        };
        var httpContext = CreateHttpContext();

        var result = await Program.HandleManualDecisionAsync(
            "wf-error",
            httpContext,
            new ManualDecisionRequest(true),
            client,
            NullLogger<Program>.Instance,
            CancellationToken.None);

        var problem = Assert.IsType<ProblemHttpResult>(result);

        Assert.Equal(StatusCodes.Status500InternalServerError, problem.StatusCode);
        Assert.NotNull(problem.ProblemDetails);
        Assert.Equal("Decision could not be submitted.", problem.ProblemDetails!.Title);
        Assert.Equal("The manual decision event could not be raised for this workflow instance.", problem.ProblemDetails.Detail);
    }

    private static DefaultHttpContext CreateHttpContext()
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Items[Program.CorrelationIdContextKey] = "trace-test";
        return httpContext;
    }

    private sealed class FakeWorkflowDecisionClient(WorkflowDecisionState state) : IWorkflowDecisionClient
    {
        public WorkflowDecisionState State { get; } = state;

        public Exception? RaiseException { get; init; }

        public List<RaisedDecision> RaisedEvents { get; } = [];

        public Task<WorkflowDecisionState> GetDecisionStateAsync(string instanceId, CancellationToken cancellationToken) =>
            Task.FromResult(State);

        public Task RaiseDecisionAsync(
            string instanceId,
            ManualDecisionEvent decisionEvent,
            CancellationToken cancellationToken)
        {
            if (RaiseException is not null)
            {
                throw RaiseException;
            }

            RaisedEvents.Add(new RaisedDecision(instanceId, decisionEvent));
            return Task.CompletedTask;
        }
    }

    private sealed record RaisedDecision(
        string InstanceId,
        ManualDecisionEvent DecisionEvent);
}

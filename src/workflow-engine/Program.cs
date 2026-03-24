using System.Text.Json.Serialization;
using RadiusClaim.Contracts;
using Dapr.Workflow;
using WorkflowEngine.Activities;
using WorkflowEngine.Models;
using WorkflowEngine.Workflows;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});
builder.Services.AddDaprClient();
builder.Services.AddDaprWorkflow(options =>
{
    options.RegisterWorkflow<ExpenseApprovalWorkflow>(RadiusClaimDapr.Workflows.ExpenseApproval);
    options.RegisterActivity<ApproveExpenseActivity>();
    options.RegisterActivity<ProcessReimbursementActivity>();
    options.RegisterActivity<PublishNotificationActivity>();
});

var app = builder.Build();

app.UseCloudEvents();

app.MapPost("/workflows/start", async (
    ExpenseSubmission submission,
    DaprWorkflowClient workflowClient,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    var errors = ValidateSubmission(submission);
    if (errors.Count > 0)
    {
        return Results.ValidationProblem(errors);
    }

    var normalizedSubmission = NormalizeSubmission(submission);
    var instanceId = normalizedSubmission.CorrelationId;

    var existingState = await workflowClient.GetWorkflowStateAsync(instanceId, getInputsAndOutputs: true, cancellationToken);
    if (existingState?.Exists == true)
    {
        return Results.Ok(ToWorkflowStatusResponse(instanceId, existingState));
    }

    try
    {
        await workflowClient.ScheduleNewWorkflowAsync(
            RadiusClaimDapr.Workflows.ExpenseApproval,
            instanceId,
            normalizedSubmission,
            startTime: null,
            cancellationToken);

        return Results.Accepted(
            $"/workflows/{instanceId}",
            new WorkflowStartResponse(instanceId, normalizedSubmission.ExpenseId));
    }
    catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
    {
        var stateAfterFailure = await workflowClient.GetWorkflowStateAsync(instanceId, getInputsAndOutputs: true, cancellationToken);
        if (stateAfterFailure?.Exists == true)
        {
            logger.LogInformation(
                ex,
                "Workflow '{InstanceId}' already exists or became visible during scheduling for expense '{ExpenseId}'.",
                instanceId,
                normalizedSubmission.ExpenseId);

            return Results.Ok(ToWorkflowStatusResponse(instanceId, stateAfterFailure));
        }

        logger.LogError(
            ex,
            "Failed to schedule workflow '{InstanceId}' for expense '{ExpenseId}'.",
            instanceId,
            normalizedSubmission.ExpenseId);

        return Results.Problem(
            title: "Workflow could not be started.",
            detail: "The expense workflow instance could not be scheduled.",
            statusCode: StatusCodes.Status500InternalServerError);
    }
});

app.MapGet("/workflows/{instanceId}", async (
    string instanceId,
    DaprWorkflowClient workflowClient,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(instanceId))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["instanceId"] = ["Workflow instance id is required."]
        });
    }

    var normalizedInstanceId = instanceId.Trim();
    var workflowState = await workflowClient.GetWorkflowStateAsync(
        normalizedInstanceId,
        getInputsAndOutputs: true,
        cancellationToken);

    return workflowState?.Exists == true
        ? Results.Ok(ToWorkflowStatusResponse(normalizedInstanceId, workflowState))
        : Results.NotFound();
});

app.MapGet("/", () => TypedResults.Ok(new WorkflowEngineDescriptor(
    RadiusClaimDapr.AppIds.WorkflowEngine,
    RadiusClaimDapr.Workflows.ExpenseApproval,
    "phase-3",
    [nameof(ExpenseSubmission), nameof(ExpenseRecord), nameof(NotificationRequest)],
    ["service-invocation", "workflow", "state-store", "pubsub"],
    "Phase 3 workflow orchestration is live.")));

app.MapGet("/healthz", () => TypedResults.Ok(new { status = "ok" }));

app.Run();

static Dictionary<string, string[]> ValidateSubmission(ExpenseSubmission submission)
{
    var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);

    if (string.IsNullOrWhiteSpace(submission.ExpenseId))
    {
        errors[nameof(submission.ExpenseId)] = ["ExpenseId is required."];
    }

    if (string.IsNullOrWhiteSpace(submission.CorrelationId))
    {
        errors[nameof(submission.CorrelationId)] = ["CorrelationId is required."];
    }

    if (string.IsNullOrWhiteSpace(submission.EmployeeId))
    {
        errors[nameof(submission.EmployeeId)] = ["EmployeeId is required."];
    }

    if (submission.Amount <= 0)
    {
        errors[nameof(submission.Amount)] = ["Amount must be greater than zero."];
    }

    if (string.IsNullOrWhiteSpace(submission.Currency))
    {
        errors[nameof(submission.Currency)] = ["Currency is required."];
    }

    if (string.IsNullOrWhiteSpace(submission.Description))
    {
        errors[nameof(submission.Description)] = ["Description is required."];
    }

    return errors;
}

static ExpenseSubmission NormalizeSubmission(ExpenseSubmission submission)
{
    var submittedAtUtc = submission.SubmittedAtUtc == default
        ? DateTimeOffset.UtcNow
        : submission.SubmittedAtUtc.ToUniversalTime();

    return submission with
    {
        ExpenseId = submission.ExpenseId.Trim(),
        CorrelationId = submission.CorrelationId.Trim(),
        EmployeeId = submission.EmployeeId.Trim(),
        Currency = submission.Currency.Trim().ToUpperInvariant(),
        Description = submission.Description.Trim(),
        SubmittedAtUtc = submittedAtUtc
    };
}

static WorkflowStatusResponse ToWorkflowStatusResponse(string instanceId, WorkflowState workflowState)
{
    var input = TryReadPayload(() => workflowState.ReadInputAs<ExpenseSubmission>());
    var output = workflowState.IsWorkflowCompleted
        ? TryReadPayload(() => workflowState.ReadOutputAs<ExpenseApprovalWorkflowResult>())
        : null;
    var progress = TryReadPayload(() => workflowState.ReadCustomStatusAs<WorkflowProgress>());

    return new WorkflowStatusResponse(
        instanceId,
        RadiusClaimDapr.Workflows.ExpenseApproval,
        input?.ExpenseId ?? output?.ExpenseId,
        input?.CorrelationId ?? output?.CorrelationId ?? instanceId,
        workflowState.RuntimeStatus.ToString(),
        workflowState.IsWorkflowRunning,
        workflowState.IsWorkflowCompleted,
        workflowState.CreatedAt,
        workflowState.LastUpdatedAt,
        progress,
        output,
        input,
        workflowState.FailureDetails?.ToString());
}

static T? TryReadPayload<T>(Func<T> reader)
{
    try
    {
        return reader();
    }
    catch
    {
        return default;
    }
}

internal sealed record WorkflowEngineDescriptor(
    string Service,
    string Workflow,
    string Phase,
    IReadOnlyList<string> Contracts,
    IReadOnlyList<string> DaprCapabilities,
    string NextStep);

internal sealed record WorkflowStartResponse(
    string InstanceId,
    string ExpenseId);

internal sealed record WorkflowStatusResponse(
    string InstanceId,
    string Workflow,
    string? ExpenseId,
    string CorrelationId,
    string RuntimeStatus,
    bool IsRunning,
    bool IsCompleted,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset LastUpdatedAtUtc,
    WorkflowProgress? Progress,
    ExpenseApprovalWorkflowResult? Output,
    ExpenseSubmission? Input,
    string? FailureDetails);

public partial class Program;

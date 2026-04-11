using System.Text.Json.Serialization;
using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr.Workflow;
using WorkflowEngine;
using WorkflowEngine.Activities;
using WorkflowEngine.Models;
using WorkflowEngine.Workflows;
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;

const string CorrelationIdContextKey = "CorrelationId";
const string CorrelationIdHeader = "X-Correlation-ID";

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
    options.RegisterActivity<RecordApprovalActivity>();
    options.RegisterActivity<RejectExpenseActivity>();
});

// Bind from appsettings.json; override with APPROVAL_THRESHOLD_USD / APPROVAL_TIMEOUT_HOURS env vars if set.
builder.Services.Configure<ApprovalOptions>(builder.Configuration.GetSection("ApprovalThreshold"));
builder.Services.PostConfigure<ApprovalOptions>(options =>
{
    var rawThreshold = builder.Configuration["APPROVAL_THRESHOLD_USD"];
    if (!string.IsNullOrEmpty(rawThreshold) &&
        decimal.TryParse(rawThreshold, System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var parsedThreshold))
    {
        options.ThresholdUsd = parsedThreshold;
    }

    var rawTimeout = builder.Configuration["APPROVAL_TIMEOUT_HOURS"];
    if (!string.IsNullOrEmpty(rawTimeout) &&
        int.TryParse(rawTimeout, out var parsedTimeout) && parsedTimeout > 0)
    {
        options.ManualApprovalTimeoutHours = parsedTimeout;
    }
});

// OpenTelemetry: configure tracing and logging
// Traces are exported to Jaeger (see docs/OBSERVABILITY.md for setup)
var jaegerAgentHost = Environment.GetEnvironmentVariable("JAEGER_AGENT_HOST") ?? "localhost";
var jaegerAgentPortStr = Environment.GetEnvironmentVariable("JAEGER_AGENT_PORT") ?? "6831";
if (!int.TryParse(jaegerAgentPortStr, out var jaegerAgentPort))
{
    jaegerAgentPort = 6831;
}

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing =>
    {
        tracing
            .SetResourceBuilder(
                ResourceBuilder.CreateDefault()
                    .AddService("workflow-engine"))
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddJaegerExporter(options =>
            {
                options.AgentHost = jaegerAgentHost;
                options.AgentPort = jaegerAgentPort;
            });
    });

builder.Logging.AddOpenTelemetry(options =>
{
    options.SetResourceBuilder(
        ResourceBuilder.CreateDefault()
            .AddService("workflow-engine"));
});

var app = builder.Build();

// Wait for Dapr sidecar gRPC port to be ready (critical for workflow client)
// The workflow gRPC port is used for bidirectional streaming with the workflow runtime
var grpcPort = Environment.GetEnvironmentVariable("DAPR_GRPC_PORT") ?? "50001";
var maxRetries = 60;
var retryCount = 0;

var startupLogger = app.Services.GetRequiredService<ILogger<Program>>();
startupLogger.LogInformation("Waiting for Dapr sidecar gRPC port {GrpcPort}...", grpcPort);
while (retryCount < maxRetries)
{
    try
    {
        using (var socket = new System.Net.Sockets.Socket(System.Net.Sockets.AddressFamily.InterNetwork, System.Net.Sockets.SocketType.Stream, System.Net.Sockets.ProtocolType.Tcp))
        {
            socket.Connect("127.0.0.1", int.Parse(grpcPort));
            startupLogger.LogInformation("✓ Dapr gRPC port is listening");
            break;
        }
    }
    catch
    {
        // Port not ready yet
    }

    retryCount++;
    if (retryCount < maxRetries)
    {
        await Task.Delay(500);
    }
}

if (retryCount >= maxRetries)
{
    startupLogger.LogWarning("⚠ Dapr gRPC port did not become available within timeout (30s). Proceeding with caution.");
}

app.UseCloudEvents();

// Correlation ID middleware: extract from header or generate a new one
var correlationLogger = app.Services.GetRequiredService<ILogger<Program>>();
app.Use(async (context, next) =>
{
    var traceId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault();
    if (string.IsNullOrWhiteSpace(traceId))
    {
        traceId = Guid.NewGuid().ToString();
    }

    context.Items[CorrelationIdContextKey] = traceId;
    context.Response.Headers.Append(CorrelationIdHeader, traceId);

    correlationLogger.LogInformation(
        "Workflow request started: {Method} {Path} [TraceId: {TraceId}]",
        context.Request.Method,
        context.Request.Path,
        traceId);

    await next();

    correlationLogger.LogInformation(
        "Workflow request completed: {Method} {Path} {StatusCode} [TraceId: {TraceId}]",
        context.Request.Method,
        context.Request.Path,
        context.Response.StatusCode,
        traceId);
});

// Read the Dapr App API token used to authenticate service-to-service calls.
// When APP_API_TOKEN is set, Dapr sidecars automatically inject a matching
// dapr-api-token header on every forwarded request. The /decide endpoint
// validates this header; in non-development environments the token is required.
var appApiToken = app.Configuration["APP_API_TOKEN"] ?? app.Configuration["Dapr:AppApiToken"];
if (string.IsNullOrEmpty(appApiToken))
{
    startupLogger.LogWarning(
        "⚠ APP_API_TOKEN is not set. The /decide endpoint will reject all requests " +
        "in non-development environments. Set APP_API_TOKEN to enable service-to-service auth.");
}

app.MapPost("/workflows/start", async (
    HttpContext context,
    ExpenseSubmission submission,
    DaprWorkflowClient workflowClient,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    var traceId = context.Items[CorrelationIdContextKey] as string ?? "unknown";
    var errors = ValidateSubmission(submission);
    if (errors.Count > 0)
    {
        return Results.ValidationProblem(errors);
    }

    var normalizedSubmission = NormalizeSubmission(submission);
    var instanceId = normalizedSubmission.CorrelationId;

    var retries = 0;
    const int maxRetries = 5;
    const int delayMs = 2000;

    while (retries < maxRetries)
    {
        try
        {
            await workflowClient.ScheduleNewWorkflowAsync(
                RadiusClaimDapr.Workflows.ExpenseApproval,
                instanceId,
                normalizedSubmission,
                startTime: null,
                cancellationToken);

            logger.LogInformation(
                "Workflow {InstanceId} scheduled successfully for expense {ExpenseId} after {Retries} attempts [TraceId: {TraceId}]",
                instanceId,
                normalizedSubmission.ExpenseId,
                retries,
                traceId);

            logger.LogInformation(
                "Workflow start request accepted for expense {ExpenseId} with instanceId {InstanceId} [TraceId: {TraceId}]",
                normalizedSubmission.ExpenseId,
                instanceId,
                traceId);

            return Results.Accepted(
                $"/workflows/{instanceId}",
                new WorkflowStartResponse(instanceId, normalizedSubmission.ExpenseId));
        }
        catch (Exception ex)
        {
            retries++;
            logger.LogWarning(
                ex,
                "Attempt {Attempt}/{MaxRetries} to schedule workflow {InstanceId} failed. Retrying in {DelayMs}ms [TraceId: {TraceId}]",
                retries,
                maxRetries,
                instanceId,
                delayMs,
                traceId);

            if (retries < maxRetries)
            {
                await Task.Delay(delayMs, cancellationToken);
            }
        }
    }

    throw new InvalidOperationException(
        $"Failed to schedule workflow {instanceId} for expense {normalizedSubmission.ExpenseId} after {maxRetries} attempts [TraceId: {traceId}]");
});

app.MapGet("/workflows/{instanceId}", async (
    string instanceId,
    HttpContext context,
    DaprWorkflowClient workflowClient,
    CancellationToken cancellationToken) =>
{
    var traceId = context.Items[CorrelationIdContextKey] as string ?? "unknown";

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

// POST /workflows/{instanceId}/decide — raises the manual-approval event to resume a paused workflow.
// Called by expense-api approve/reject endpoints via Dapr service invocation.
// Requires a valid dapr-api-token header when APP_API_TOKEN is configured.
app.MapPost("/workflows/{instanceId}/decide", async (
    string instanceId,
    HttpContext context,
    ManualDecisionRequest decisionRequest,
    DaprWorkflowClient workflowClient,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    var traceId = context.Items[CorrelationIdContextKey] as string ?? "unknown";

    // Auth: validate incoming Dapr App API token.
    // In production (APP_API_TOKEN set), the header must match exactly.
    // In non-development with no token configured, fail closed.
    if (!string.IsNullOrEmpty(appApiToken))
    {
        var incoming = context.Request.Headers["dapr-api-token"].FirstOrDefault();
        if (string.IsNullOrEmpty(incoming) || incoming != appApiToken)
        {
            logger.LogWarning(
                "Unauthorized /decide request — invalid or missing dapr-api-token [TraceId: {TraceId}]",
                traceId);
            return Results.Unauthorized();
        }
    }
    else if (!app.Environment.IsDevelopment())
    {
        logger.LogError(
            "APP_API_TOKEN not configured — /decide is blocked in non-development environments [TraceId: {TraceId}]",
            traceId);
        return Results.Unauthorized();
    }

    // Validate decision request fields before touching workflow state.
    var decisionErrors = ValidateDecisionRequest(decisionRequest);
    if (decisionErrors.Count > 0)
    {
        return Results.ValidationProblem(decisionErrors);
    }

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
        getInputsAndOutputs: false,
        cancellationToken);

    if (workflowState?.Exists != true)
    {
        logger.LogWarning(
            "Decision request for non-existent workflow {InstanceId} [TraceId: {TraceId}]",
            normalizedInstanceId,
            traceId);

        return Results.NotFound();
    }

    if (!workflowState.IsWorkflowRunning)
    {
        logger.LogWarning(
            "Decision request for non-running workflow {InstanceId}, status: {Status} [TraceId: {TraceId}]",
            normalizedInstanceId,
            workflowState.RuntimeStatus,
            traceId);

        return Results.Conflict(new
        {
            error = "Workflow is not running and cannot accept a decision.",
            instanceId = normalizedInstanceId,
            runtimeStatus = workflowState.RuntimeStatus.ToString()
        });
    }

    var reason = string.IsNullOrWhiteSpace(decisionRequest.Reason)
        ? (decisionRequest.Approved ? null : "Manual rejection by approver")
        : decisionRequest.Reason;

    var decisionEvent = new ManualDecisionEvent(decisionRequest.Approved, reason);

    try
    {
        await workflowClient.RaiseEventAsync(
            normalizedInstanceId,
            ExpenseApprovalWorkflow.ManualDecisionEventName,
            decisionEvent,
            cancellationToken);

        logger.LogInformation(
            "Decision {Decision} raised for workflow {InstanceId} [TraceId: {TraceId}]",
            decisionRequest.Approved ? "Approved" : "Rejected",
            normalizedInstanceId,
            traceId);

        return Results.Accepted(
            $"/workflows/{normalizedInstanceId}",
            new { instanceId = normalizedInstanceId, decision = decisionRequest.Approved ? "Approved" : "Rejected" });
    }
    catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogError(
            ex,
            "Failed to raise decision event for workflow {InstanceId} [TraceId: {TraceId}]",
            normalizedInstanceId,
            traceId);

        return Results.Problem(
            title: "Decision could not be submitted.",
            detail: "The manual decision event could not be raised for this workflow instance.",
            statusCode: StatusCodes.Status500InternalServerError);
    }
});

app.MapGet("/", () => TypedResults.Ok(new WorkflowEngineDescriptor(
    RadiusClaimDapr.AppIds.WorkflowEngine,
    RadiusClaimDapr.Workflows.ExpenseApproval,
    typeof(Program).Assembly.GetName().Version?.ToString() ?? "unknown",
    [nameof(ExpenseSubmission), nameof(ExpenseRecord), nameof(NotificationRequest)],
    ["service-invocation", "workflow", "state-store", "pubsub"],
    "Workflow orchestration is live.")));

app.MapGet("/healthz", () => TypedResults.Ok(new { status = "ok" }));

app.Run();

static Dictionary<string, string[]> ValidateSubmission(ExpenseSubmission submission)
{
    const int maxIdLength = 128;
    const int maxDescriptionLength = 1000;
    const decimal maxAmountUsd = 1_000_000m;

    var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);

    if (string.IsNullOrWhiteSpace(submission.ExpenseId))
        errors[nameof(submission.ExpenseId)] = ["ExpenseId is required."];
    else if (submission.ExpenseId.Trim().Length > maxIdLength)
        errors[nameof(submission.ExpenseId)] = [$"ExpenseId must not exceed {maxIdLength} characters."];

    if (string.IsNullOrWhiteSpace(submission.CorrelationId))
        errors[nameof(submission.CorrelationId)] = ["CorrelationId is required."];
    else if (submission.CorrelationId.Trim().Length > maxIdLength)
        errors[nameof(submission.CorrelationId)] = [$"CorrelationId must not exceed {maxIdLength} characters."];

    if (string.IsNullOrWhiteSpace(submission.EmployeeId))
        errors[nameof(submission.EmployeeId)] = ["EmployeeId is required."];
    else if (submission.EmployeeId.Trim().Length > maxIdLength)
        errors[nameof(submission.EmployeeId)] = [$"EmployeeId must not exceed {maxIdLength} characters."];

    if (submission.Amount <= 0)
        errors[nameof(submission.Amount)] = ["Amount must be greater than zero."];
    else if (submission.Amount > maxAmountUsd)
        errors[nameof(submission.Amount)] = [$"Amount must not exceed {maxAmountUsd:F2}."];

    if (string.IsNullOrWhiteSpace(submission.Currency))
        errors[nameof(submission.Currency)] = ["Currency is required."];

    if (string.IsNullOrWhiteSpace(submission.Description))
        errors[nameof(submission.Description)] = ["Description is required."];
    else if (submission.Description.Trim().Length > maxDescriptionLength)
        errors[nameof(submission.Description)] = [$"Description must not exceed {maxDescriptionLength} characters."];

    return errors;
}

static Dictionary<string, string[]> ValidateDecisionRequest(ManualDecisionRequest request)
{
    const int maxReasonLength = 1000;

    var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);

    if (request.Reason is not null && request.Reason.Length > maxReasonLength)
    {
        errors[nameof(request.Reason)] = [$"Reason must not exceed {maxReasonLength} characters."];
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
    string Version,
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

/// <summary>Request body for the POST /workflows/{instanceId}/decide endpoint.</summary>
internal sealed record ManualDecisionRequest(
    bool Approved,
    string? Reason = null);

public partial class Program;

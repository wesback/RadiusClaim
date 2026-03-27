using RadiusClaim.Contracts;
using Dapr.Client;
using System.Net.Http;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});
builder.Services.AddDaprClient();

var app = builder.Build();

app.UseStaticFiles();
app.UseCloudEvents();
app.Use(async (context, next) =>
{
    try
    {
        await next();
    }
    catch (Dapr.DaprException ex) when (!context.RequestAborted.IsCancellationRequested)
    {
        app.Logger.LogWarning(
            ex,
            "Dapr dependency unavailable while handling {Method} {Path}.",
            context.Request.Method,
            context.Request.Path);

        if (context.Response.HasStarted)
        {
            throw;
        }

        context.Response.Clear();
        await Results.Problem(
            title: "Expense state is unavailable.",
            detail: "The hosted /app shell can render on its own, but loading or submitting expenses requires the expense-api Dapr sidecar and the configured 'statestore' component. Start expense-api with Dapr. Workflow telemetry also depends on workflow-engine being reachable through Dapr.",
            statusCode: StatusCodes.Status503ServiceUnavailable)
            .ExecuteAsync(context);
    }
});

var expenses = app.MapGroup("/expenses");

expenses.MapPost("/", async (ExpenseSubmission submission, DaprClient daprClient, CancellationToken cancellationToken) =>
{
    var errors = ValidateSubmission(submission);
    if (errors.Count > 0)
    {
        return Results.ValidationProblem(errors);
    }

    var nowUtc = DateTimeOffset.UtcNow;
    var expenseId = CoalesceOrCreate(submission.ExpenseId);
    var correlationId = CoalesceOrCreate(submission.CorrelationId);
    var stateKey = RadiusClaimDapr.StateKeys.Expense(expenseId);
    var allowGeneratedCorrelationMatch = string.IsNullOrWhiteSpace(submission.CorrelationId);
    var allowGeneratedSubmittedAtMatch = submission.SubmittedAtUtc == default;

    var submittedAtUtc = submission.SubmittedAtUtc == default
        ? nowUtc
        : submission.SubmittedAtUtc.ToUniversalTime();

    var record = new ExpenseRecord(
        expenseId,
        correlationId,
        submission.EmployeeId.Trim(),
        submission.Amount,
        submission.Currency.Trim().ToUpperInvariant(),
        submission.Description.Trim(),
        ExpenseStatus.Submitted,
        submittedAtUtc,
        nowUtc);

    var createOutcome = await TryCreateExpenseRecordAsync(
        stateKey,
        record,
        allowGeneratedCorrelationMatch,
        allowGeneratedSubmittedAtMatch,
        daprClient,
        cancellationToken);

    if (createOutcome.Result == ExpenseCreateResult.NotPersisted)
    {
        return Results.Problem(
            title: "Expense submission could not be completed.",
            detail: "The expense record was not persisted.",
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }

    if (createOutcome.Result == ExpenseCreateResult.AlreadyExists)
    {
        var existingRecord = createOutcome.Record ?? record;
        return Results.Problem(
            title: "Expense already exists.",
            detail: $"Expense '{expenseId}' already exists. Fetch it directly at /expenses/{expenseId}.",
            statusCode: StatusCodes.Status409Conflict,
            extensions: CreateExpenseErrorExtensions(existingRecord));
    }

    var persistedRecord = createOutcome.Record ?? record;
    var indexOutcome = await TryAddExpenseToIndexAsync(expenseId, daprClient, cancellationToken);
    if (indexOutcome == ExpenseIndexMutationResult.Failed)
    {
        return Results.Problem(
            title: "Expense was saved, but follow-up indexing failed.",
            detail: $"Expense '{expenseId}' was persisted, but the recent-expense list could not be updated. Fetch it directly at /expenses/{expenseId}.",
            statusCode: StatusCodes.Status500InternalServerError,
            extensions: CreateExpenseErrorExtensions(persistedRecord));
    }

    var workflowSubmission = ToWorkflowSubmission(persistedRecord);
    await TryStartExpenseWorkflowAsync(workflowSubmission, daprClient, app.Logger, cancellationToken);

    return createOutcome.Result switch
    {
        ExpenseCreateResult.Created => Results.Created($"/expenses/{expenseId}", persistedRecord),
        ExpenseCreateResult.MatchedExistingRecord => Results.Ok(persistedRecord),
        _ => throw new InvalidOperationException($"Unexpected expense create result '{createOutcome.Result}'.")
    };
});

expenses.MapGet("/{id}/workflow", async (
    string id,
    DaprClient daprClient,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(id))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["id"] = ["Expense id is required."]
        });
    }

    var normalizedId = id.Trim();
    var record = await daprClient.GetStateAsync<ExpenseRecord>(
        RadiusClaimDapr.Components.StateStore,
        RadiusClaimDapr.StateKeys.Expense(normalizedId),
        consistencyMode: ConsistencyMode.Strong,
        cancellationToken: cancellationToken);

    if (record is null)
    {
        return Results.NotFound();
    }

    var workflowSnapshot = await GetExpenseWorkflowSnapshotAsync(record, logger, cancellationToken);
    return Results.Ok(workflowSnapshot);
});

// POST /expenses/{id}/approve — signals the paused workflow to approve the expense.
expenses.MapPost("/{id}/approve", async (
    string id,
    ExpenseApprovalActionRequest? body,
    DaprClient daprClient,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
    await HandleExpenseApprovalActionAsync(id, approved: true, body?.Reason, daprClient, logger, cancellationToken));

// POST /expenses/{id}/reject — signals the paused workflow to reject the expense.
expenses.MapPost("/{id}/reject", async (
    string id,
    ExpenseApprovalActionRequest? body,
    DaprClient daprClient,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
    await HandleExpenseApprovalActionAsync(id, approved: false, body?.Reason, daprClient, logger, cancellationToken));

expenses.MapGet("/{id}", async (string id, DaprClient daprClient, CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(id))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["id"] = ["Expense id is required."]
        });
    }

    var record = await daprClient.GetStateAsync<ExpenseRecord>(
        RadiusClaimDapr.Components.StateStore,
        RadiusClaimDapr.StateKeys.Expense(id.Trim()),
        consistencyMode: ConsistencyMode.Strong,
        cancellationToken: cancellationToken);

    return record is null
        ? Results.NotFound()
        : Results.Ok(record);
});

// GET /expenses?page=1&pageSize=20
// Returns a paginated envelope: { items, total, page, pageSize, hasMore }
// page defaults to 1, pageSize defaults to 20 (max 100).
expenses.MapGet("/", async (
    DaprClient daprClient,
    CancellationToken cancellationToken,
    int page = 1,
    int pageSize = 20) =>
{
    if (page < 1)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["page"] = ["Page must be 1 or greater."]
        });
    }

    if (pageSize < 1 || pageSize > 100)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["pageSize"] = ["pageSize must be between 1 and 100."]
        });
    }

    var expenseIndex = await GetExpenseIndexAsync(daprClient, cancellationToken);
    var total = expenseIndex.Count;

    if (total == 0)
    {
        return Results.Ok(new ExpensePagedResult([], 0, page, pageSize, false));
    }

    var pageIds = expenseIndex
        .Skip((page - 1) * pageSize)
        .Take(pageSize)
        .ToArray();

    var records = await Task.WhenAll(pageIds.Select(expenseId =>
        daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.StateStore,
            RadiusClaimDapr.StateKeys.Expense(expenseId),
            consistencyMode: ConsistencyMode.Strong,
            cancellationToken: cancellationToken)));

    var items = records.Where(record => record is not null).ToArray();
    var hasMore = page * pageSize < total;

    return Results.Ok(new ExpensePagedResult(items!, total, page, pageSize, hasMore));
});

app.MapGet("/app", () => Results.Redirect("/app/index.html"));
app.MapGet("/", () => TypedResults.Ok(new ServiceDescriptor(
    RadiusClaimDapr.AppIds.ExpenseApi,
    "phase-3",
    [nameof(ExpenseSubmission), nameof(ExpenseRecord), nameof(ExpenseStatus)],
    ["service-invocation", "state-store"],
    "Expense persistence now invokes the workflow engine after successful storage.")));

app.MapGet("/healthz", () => TypedResults.Ok(new { status = "ok" }));

app.Run();

static Dictionary<string, string[]> ValidateSubmission(ExpenseSubmission submission)
{
    var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);

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

static async Task<IReadOnlyList<string>> GetExpenseIndexAsync(DaprClient daprClient, CancellationToken cancellationToken)
{
    var expenseIndex = await daprClient.GetStateAsync<string[]>(
        RadiusClaimDapr.Components.StateStore,
        RadiusClaimDapr.StateKeys.ExpenseIndex,
        consistencyMode: ConsistencyMode.Strong,
        cancellationToken: cancellationToken);

    return NormalizeExpenseIndex(expenseIndex);
}

static async Task<ExpenseIndexMutationResult> TryAddExpenseToIndexAsync(
    string expenseId,
    DaprClient daprClient,
    CancellationToken cancellationToken)
{
    for (var attempt = 0; attempt < 5; attempt++)
    {
        var expenseIndexEntry = await daprClient.GetStateEntryAsync<string[]>(
            RadiusClaimDapr.Components.StateStore,
            RadiusClaimDapr.StateKeys.ExpenseIndex,
            consistencyMode: ConsistencyMode.Strong,
            cancellationToken: cancellationToken);

        var expenseIndex = NormalizeExpenseIndex(expenseIndexEntry.Value);
        if (expenseIndex.Contains(expenseId, StringComparer.Ordinal))
        {
            return ExpenseIndexMutationResult.AlreadyPresent;
        }

        expenseIndexEntry.Value = [expenseId, .. expenseIndex];

        var saved = await expenseIndexEntry.TrySaveAsync(
            new StateOptions
            {
                Consistency = ConsistencyMode.Strong,
                Concurrency = ConcurrencyMode.FirstWrite
            },
            cancellationToken: cancellationToken);

        if (saved)
        {
            return ExpenseIndexMutationResult.Added;
        }

        if (attempt < 4)
        {
            await Task.Delay(TimeSpan.FromMilliseconds(25 * (attempt + 1)), cancellationToken);
        }
    }

    return ExpenseIndexMutationResult.Failed;
}

static async Task<ExpenseCreateOutcome> TryCreateExpenseRecordAsync(
    string stateKey,
    ExpenseRecord record,
    bool allowGeneratedCorrelationMatch,
    bool allowGeneratedSubmittedAtMatch,
    DaprClient daprClient,
    CancellationToken cancellationToken)
{
    var expenseRecordEntry = await daprClient.GetStateEntryAsync<ExpenseRecord>(
        RadiusClaimDapr.Components.StateStore,
        stateKey,
        consistencyMode: ConsistencyMode.Strong,
        cancellationToken: cancellationToken);

    if (expenseRecordEntry.Value is not null)
    {
        return MatchesStoredSubmission(
            expenseRecordEntry.Value,
            record,
            allowGeneratedCorrelationMatch,
            allowGeneratedSubmittedAtMatch)
            ? new ExpenseCreateOutcome(ExpenseCreateResult.MatchedExistingRecord, expenseRecordEntry.Value)
            : new ExpenseCreateOutcome(ExpenseCreateResult.AlreadyExists, expenseRecordEntry.Value);
    }

    expenseRecordEntry.Value = record;

    try
    {
        var created = await expenseRecordEntry.TrySaveAsync(
            new StateOptions
            {
                Consistency = ConsistencyMode.Strong,
                Concurrency = ConcurrencyMode.FirstWrite
            },
            cancellationToken: cancellationToken);

        if (created)
        {
            return new ExpenseCreateOutcome(ExpenseCreateResult.Created, record);
        }
    }
    catch when (!cancellationToken.IsCancellationRequested)
    {
    }

    var persistedRecord = await daprClient.GetStateAsync<ExpenseRecord>(
        RadiusClaimDapr.Components.StateStore,
        stateKey,
        consistencyMode: ConsistencyMode.Strong,
        cancellationToken: cancellationToken);

    if (persistedRecord is null)
    {
        return new ExpenseCreateOutcome(ExpenseCreateResult.NotPersisted, null);
    }

    return MatchesStoredSubmission(
            persistedRecord,
            record,
            allowGeneratedCorrelationMatch,
            allowGeneratedSubmittedAtMatch)
        ? new ExpenseCreateOutcome(ExpenseCreateResult.MatchedExistingRecord, persistedRecord)
        : new ExpenseCreateOutcome(ExpenseCreateResult.AlreadyExists, persistedRecord);
}

static bool MatchesStoredSubmission(
    ExpenseRecord existingRecord,
    ExpenseRecord candidate,
    bool allowGeneratedCorrelationMatch,
    bool allowGeneratedSubmittedAtMatch)
{
    return existingRecord.ExpenseId == candidate.ExpenseId
        && (allowGeneratedCorrelationMatch || existingRecord.CorrelationId == candidate.CorrelationId)
        && existingRecord.EmployeeId == candidate.EmployeeId
        && existingRecord.Amount == candidate.Amount
        && existingRecord.Currency == candidate.Currency
        && existingRecord.Description == candidate.Description
        && (allowGeneratedSubmittedAtMatch || existingRecord.SubmittedAtUtc == candidate.SubmittedAtUtc);
}

static string[] NormalizeExpenseIndex(IEnumerable<string>? expenseIndex)
{
    return expenseIndex?
        .Where(expenseId => !string.IsNullOrWhiteSpace(expenseId))
        .Select(expenseId => expenseId.Trim())
        .Distinct(StringComparer.Ordinal)
        .ToArray() ?? [];
}

static string CoalesceOrCreate(string? candidate)
{
    return string.IsNullOrWhiteSpace(candidate)
        ? Guid.NewGuid().ToString("n")
        : candidate.Trim();
}

static ExpenseSubmission ToWorkflowSubmission(ExpenseRecord record)
{
    return new ExpenseSubmission(
        record.ExpenseId,
        record.CorrelationId,
        record.EmployeeId,
        record.Amount,
        record.Currency,
        record.Description,
        record.SubmittedAtUtc);
}

static Dictionary<string, object?> CreateExpenseErrorExtensions(ExpenseRecord record)
{
    return new Dictionary<string, object?>(StringComparer.Ordinal)
    {
        ["expenseId"] = record.ExpenseId,
        ["location"] = $"/expenses/{record.ExpenseId}"
    };
}

static async Task TryStartExpenseWorkflowAsync(
    ExpenseSubmission submission,
    DaprClient daprClient,
    ILogger logger,
    CancellationToken cancellationToken)
{
    try
    {
        using var workflowClient = DaprClient.CreateInvokeHttpClient(RadiusClaimDapr.AppIds.WorkflowEngine);
        using var response = await workflowClient.PostAsJsonAsync("workflows/start", submission, cancellationToken);
        response.EnsureSuccessStatusCode();
    }
    catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogWarning(
            ex,
            "Expense '{ExpenseId}' was persisted but workflow '{WorkflowInstanceId}' could not be started.",
            submission.ExpenseId,
            submission.CorrelationId);
    }
}

static async Task<IResult> HandleExpenseApprovalActionAsync(
    string id,
    bool approved,
    string? reason,
    DaprClient daprClient,
    ILogger logger,
    CancellationToken cancellationToken)
{
    if (string.IsNullOrWhiteSpace(id))
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["id"] = ["Expense id is required."]
        });
    }

    var normalizedId = id.Trim();
    var record = await daprClient.GetStateAsync<ExpenseRecord>(
        RadiusClaimDapr.Components.StateStore,
        RadiusClaimDapr.StateKeys.Expense(normalizedId),
        consistencyMode: ConsistencyMode.Strong,
        cancellationToken: cancellationToken);

    if (record is null)
    {
        return Results.NotFound();
    }

    if (record.Status != ExpenseStatus.ManualReviewRequested)
    {
        return Results.Conflict(new
        {
            error = $"Expense '{normalizedId}' is not awaiting manual approval. Current status: {record.Status}.",
            status = record.Status.ToString()
        });
    }

    try
    {
        using var workflowClient = DaprClient.CreateInvokeHttpClient(RadiusClaimDapr.AppIds.WorkflowEngine);
        var decisionBody = new { approved, reason };
        using var response = await workflowClient.PostAsJsonAsync(
            $"workflows/{Uri.EscapeDataString(record.CorrelationId)}/decide",
            decisionBody,
            cancellationToken);

        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return Results.Problem(
                title: "Workflow instance not found.",
                detail: $"No running workflow found for expense '{normalizedId}'.",
                statusCode: StatusCodes.Status404NotFound);
        }

        if (response.StatusCode == System.Net.HttpStatusCode.Conflict)
        {
            return Results.Conflict(new
            {
                error = "The workflow is no longer waiting for a decision.",
                expenseId = normalizedId
            });
        }

        response.EnsureSuccessStatusCode();

        logger.LogInformation(
            "Expense '{ExpenseId}' {Decision} signal sent to workflow '{InstanceId}'.",
            normalizedId,
            approved ? "approval" : "rejection",
            record.CorrelationId);

        return Results.Accepted(
            $"/expenses/{normalizedId}/workflow",
            new { expenseId = normalizedId, decision = approved ? "Approved" : "Rejected" });
    }
    catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogWarning(
            ex,
            "Could not send {Decision} signal to workflow for expense '{ExpenseId}'.",
            approved ? "approval" : "rejection",
            normalizedId);

        return Results.Problem(
            title: "Could not deliver decision to workflow.",
            detail: "The approval/rejection signal could not be forwarded to the workflow engine.",
            statusCode: StatusCodes.Status502BadGateway);
    }
}

static async Task<ExpenseWorkflowSnapshot> GetExpenseWorkflowSnapshotAsync(
    ExpenseRecord record,
    ILogger logger,
    CancellationToken cancellationToken)
{
    try
    {
        using var workflowClient = DaprClient.CreateInvokeHttpClient(RadiusClaimDapr.AppIds.WorkflowEngine);
        var workflowStatus = await workflowClient.GetFromJsonAsync<ExpenseWorkflowStatus>(
            $"workflows/{Uri.EscapeDataString(record.CorrelationId)}",
            cancellationToken);

        return workflowStatus is null
            ? CreatePendingWorkflowSnapshot(record)
            : ToExpenseWorkflowSnapshot(record, workflowStatus);
    }
    catch (HttpRequestException ex) when (!cancellationToken.IsCancellationRequested && ex.StatusCode == HttpStatusCode.NotFound)
    {
        return CreatePendingWorkflowSnapshot(record);
    }
    catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogWarning(
            ex,
            "Workflow details for expense '{ExpenseId}' are temporarily unavailable.",
            record.ExpenseId);

        return CreateUnavailableWorkflowSnapshot(record);
    }
}

static ExpenseWorkflowSnapshot ToExpenseWorkflowSnapshot(
    ExpenseRecord record,
    ExpenseWorkflowStatus workflowStatus)
{
    var finalStatus = workflowStatus.Output?.FinalStatus;
    var summary = finalStatus switch
    {
        ExpenseStatus.Reimbursed => "Reimbursement completed and the workflow is closed.",
        ExpenseStatus.ManualReviewRequested => "The amount crossed the threshold and is waiting on a human decision.",
        ExpenseStatus.Approved => "The expense is approved and moving toward reimbursement.",
        ExpenseStatus.Rejected => "The workflow completed with a rejection outcome.",
        _ when workflowStatus.IsRunning => "The workflow is actively moving this expense through validation and decisioning.",
        _ when string.Equals(workflowStatus.RuntimeStatus, "Pending", StringComparison.OrdinalIgnoreCase) => "The workflow has been scheduled and is waiting to run.",
        _ => "Workflow telemetry is available for this expense."
    };

    return new ExpenseWorkflowSnapshot(
        record.ExpenseId,
        record.CorrelationId,
        workflowStatus.InstanceId,
        workflowStatus.IsCompleted ? "Completed" : workflowStatus.IsRunning ? "Running" : workflowStatus.RuntimeStatus,
        summary,
        workflowStatus.RuntimeStatus,
        workflowStatus.Progress?.Step,
        workflowStatus.Output?.DecisionSource,
        finalStatus,
        workflowStatus.Output?.NotificationEventType,
        workflowStatus.IsCompleted,
        workflowStatus.IsRunning,
        workflowStatus.CreatedAtUtc,
        workflowStatus.LastUpdatedAtUtc,
        workflowStatus.FailureDetails);
}

static ExpenseWorkflowSnapshot CreatePendingWorkflowSnapshot(ExpenseRecord record)
{
    return new ExpenseWorkflowSnapshot(
        record.ExpenseId,
        record.CorrelationId,
        record.CorrelationId,
        "Pending",
        "The workflow is still spinning up. Refresh again in a moment.",
        "Pending",
        "Queued",
        null,
        null,
        null,
        false,
        false,
        null,
        null,
        null);
}

static ExpenseWorkflowSnapshot CreateUnavailableWorkflowSnapshot(ExpenseRecord record)
{
    return new ExpenseWorkflowSnapshot(
        record.ExpenseId,
        record.CorrelationId,
        record.CorrelationId,
        "Unavailable",
        "The expense record is available, but workflow telemetry needs workflow-engine to be reachable through Dapr.",
        null,
        null,
        null,
        null,
        null,
        false,
        false,
        null,
        null,
        null);
}

internal sealed record ServiceDescriptor(
    string Service,
    string Phase,
    IReadOnlyList<string> Contracts,
    IReadOnlyList<string> DaprCapabilities,
    string NextStep);

internal sealed record ExpenseCreateOutcome(
    ExpenseCreateResult Result,
    ExpenseRecord? Record);

internal enum ExpenseIndexMutationResult
{
    Added,
    AlreadyPresent,
    Failed
}

internal enum ExpenseCreateResult
{
    Created,
    MatchedExistingRecord,
    AlreadyExists,
    NotPersisted
}

internal sealed record ExpenseWorkflowStatus(
    string InstanceId,
    string Workflow,
    string? ExpenseId,
    string CorrelationId,
    string RuntimeStatus,
    bool IsRunning,
    bool IsCompleted,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset LastUpdatedAtUtc,
    ExpenseWorkflowProgress? Progress,
    ExpenseWorkflowResult? Output,
    ExpenseSubmission? Input,
    string? FailureDetails);

internal sealed record ExpenseWorkflowProgress(
    string ExpenseId,
    string CorrelationId,
    ExpenseStatus Status,
    string Step);

internal sealed record ExpenseWorkflowResult(
    string ExpenseId,
    string CorrelationId,
    ExpenseStatus FinalStatus,
    NotificationEventType NotificationEventType,
    string DecisionSource);

internal sealed record ExpenseWorkflowSnapshot(
    string ExpenseId,
    string CorrelationId,
    string InstanceId,
    string State,
    string Summary,
    string? RuntimeStatus,
    string? CurrentStep,
    string? DecisionSource,
    ExpenseStatus? FinalStatus,
    NotificationEventType? NotificationEventType,
    bool IsCompleted,
    bool IsRunning,
    DateTimeOffset? CreatedAtUtc,
    DateTimeOffset? LastUpdatedAtUtc,
    string? FailureDetails);

/// <summary>Optional body for approve/reject endpoints. Both fields are optional.</summary>
internal sealed record ExpenseApprovalActionRequest(string? Reason = null);

/// <summary>Paginated result envelope for GET /expenses.</summary>
/// <param name="Items">The expenses on the current page.</param>
/// <param name="Total">Total number of expenses across all pages.</param>
/// <param name="Page">Current page number (1-based).</param>
/// <param name="PageSize">Number of items per page.</param>
/// <param name="HasMore">True when additional pages exist beyond the current page.</param>
internal sealed record ExpensePagedResult(
    ExpenseRecord[] Items,
    int Total,
    int Page,
    int PageSize,
    bool HasMore);

public partial class Program;

using RadiusClaim.Contracts;
using Dapr.Client;
using System.Net.Http;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});
builder.Services.AddDaprClient();

var app = builder.Build();

app.UseCloudEvents();

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
        return Results.Conflict(new
        {
            message = $"Expense '{expenseId}' already exists."
        });
    }

    var persistedRecord = createOutcome.Record ?? record;
    var indexOutcome = await TryAddExpenseToIndexAsync(expenseId, daprClient, cancellationToken);
    if (indexOutcome == ExpenseIndexMutationResult.Failed)
    {
        return Results.Json(new
        {
            message = "Expense was persisted, but the recent-expense index could not be updated.",
            expense = persistedRecord,
            location = $"/expenses/{expenseId}"
        }, statusCode: StatusCodes.Status500InternalServerError);
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

expenses.MapGet("/", async (DaprClient daprClient, CancellationToken cancellationToken) =>
{
    var expenseIndex = await GetExpenseIndexAsync(daprClient, cancellationToken);
    if (expenseIndex.Count == 0)
    {
        return Results.Ok(Array.Empty<ExpenseRecord>());
    }

    var records = await Task.WhenAll(expenseIndex.Select(expenseId =>
        daprClient.GetStateAsync<ExpenseRecord>(
            RadiusClaimDapr.Components.StateStore,
            RadiusClaimDapr.StateKeys.Expense(expenseId),
            consistencyMode: ConsistencyMode.Strong,
            cancellationToken: cancellationToken)));

    return Results.Ok(records.Where(record => record is not null).ToArray());
});

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

public partial class Program;

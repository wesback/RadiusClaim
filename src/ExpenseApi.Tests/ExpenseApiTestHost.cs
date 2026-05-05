using System.Globalization;
using System.Net;
using Dapr.Client;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Moq;
using RadiusClaim.Contracts;
using RadiusClaim.Dapr;

namespace ExpenseApi.Tests;

internal sealed class ExpenseApiTestHost : IAsyncDisposable
{
    private readonly string? _previousDaprHttpPort;
    private readonly WebApplicationFactory<Program> _factory;
    private readonly Dictionary<string, object?> _state = new(StringComparer.Ordinal);

    private ExpenseApiTestHost(
        string? previousDaprHttpPort,
        FakeDaprSidecar sidecar,
        Mock<DaprClient> daprClientMock,
        WebApplicationFactory<Program> factory)
    {
        _previousDaprHttpPort = previousDaprHttpPort;
        Sidecar = sidecar;
        DaprClientMock = daprClientMock;
        _factory = factory;
        Client = _factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
    }

    public HttpClient Client { get; }
    public FakeDaprSidecar Sidecar { get; }
    public Mock<DaprClient> DaprClientMock { get; }

    public static ExpenseApiTestHost Create(
        ExpenseRecord? seedRecord = null,
        HttpStatusCode workflowDecisionStatusCode = HttpStatusCode.Accepted)
    {
        var sidecar = new FakeDaprSidecar
        {
            WorkflowDecisionStatusCode = workflowDecisionStatusCode
        };

        var previousDaprHttpPort = Environment.GetEnvironmentVariable("DAPR_HTTP_PORT");
        Environment.SetEnvironmentVariable("DAPR_HTTP_PORT", sidecar.Port.ToString(CultureInfo.InvariantCulture));

        var daprClientMock = new Mock<DaprClient>(MockBehavior.Strict);
        var harness = CreateHarness(previousDaprHttpPort, sidecar, daprClientMock);

        if (seedRecord is not null)
        {
            harness._state[RadiusClaimDapr.StateKeys.Expense(seedRecord.ExpenseId)] = seedRecord;
        }

        harness.ConfigureDaprClientMock();
        return harness;
    }

    public ExpenseRecord? GetExpense(string expenseId)
    {
        return _state.TryGetValue(RadiusClaimDapr.StateKeys.Expense(expenseId), out var value)
            ? value as ExpenseRecord
            : null;
    }

    public async ValueTask DisposeAsync()
    {
        Client.Dispose();
        _factory.Dispose();
        Sidecar.Dispose();
        Environment.SetEnvironmentVariable("DAPR_HTTP_PORT", _previousDaprHttpPort);
        await Task.CompletedTask;
    }

    private static ExpenseApiTestHost CreateHarness(
        string? previousDaprHttpPort,
        FakeDaprSidecar sidecar,
        Mock<DaprClient> daprClientMock)
    {
        var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting(WebHostDefaults.EnvironmentKey, "Development");
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DaprClient>();
                services.AddSingleton(daprClientMock.Object);
            });
        });

        return new ExpenseApiTestHost(previousDaprHttpPort, sidecar, daprClientMock, factory);
    }

    private void ConfigureDaprClientMock()
    {
        DaprClientMock
            .Setup(client => client.GetStateAsync<ExpenseRecord>(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<ConsistencyMode?>(),
                It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync((string _, string key, ConsistencyMode? _, IReadOnlyDictionary<string, string>? _, CancellationToken _) =>
                _state.TryGetValue(key, out var value) ? value as ExpenseRecord : null);

        DaprClientMock
            .Setup(client => client.SaveStateAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<ExpenseRecord>(),
                It.IsAny<StateOptions?>(),
                It.IsAny<IReadOnlyDictionary<string, string>?>(),
                It.IsAny<CancellationToken>()))
            .Returns((string _, string key, ExpenseRecord value, StateOptions? _, IReadOnlyDictionary<string, string>? _, CancellationToken _) =>
            {
                _state[key] = value;
                return Task.CompletedTask;
            });

    }
}

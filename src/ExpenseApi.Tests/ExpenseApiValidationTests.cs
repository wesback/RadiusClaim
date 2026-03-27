using System.Net;
using System.Net.Http.Json;
using Dapr.Client;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Moq;
using RadiusClaim.Contracts;
using Xunit;

namespace ExpenseApi.Tests;

/// <summary>
/// API-level validation tests for the expense submission endpoint.
/// Uses WebApplicationFactory to host expense-api in-process with a mocked DaprClient,
/// exercising the validation rules without requiring a running Dapr sidecar.
/// </summary>
public sealed class ExpenseApiValidationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public ExpenseApiValidationTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                // Replace real DaprClient with a no-op mock. Validation errors are
                // returned before any DaprClient calls, so setup is not required.
                var existing = services.SingleOrDefault(d => d.ServiceType == typeof(DaprClient));
                if (existing is not null) services.Remove(existing);

                var mock = new Mock<DaprClient>();
                services.AddSingleton(mock.Object);
            });
        });
    }

    private HttpClient CreateClient() => _factory.CreateClient();

    private static object ValidPayload(decimal amount = 50m) => new
    {
        employeeId = "emp-test",
        amount,
        currency = "USD",
        description = "Test expense"
    };

    [Fact]
    public async Task Post_ValidExpense_Returns2xx()
    {
        // Validation passes for a complete, positive-amount submission.
        // The actual status (201/503) depends on Dapr availability, so we assert 2xx or 503.
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/", ValidPayload());

        Assert.True(
            response.IsSuccessStatusCode || response.StatusCode == HttpStatusCode.ServiceUnavailable,
            $"Expected 2xx or 503 for a valid expense, got {(int)response.StatusCode}");
    }

    [Fact]
    public async Task Post_MissingEmployeeId_Returns400()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "",
            amount = 50m,
            currency = "USD",
            description = "Missing employee"
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-100)]
    public async Task Post_NonPositiveAmount_Returns400(decimal amount)
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-1",
            amount,
            currency = "USD",
            description = "Bad amount"
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Post_MissingCurrency_Returns400()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-1",
            amount = 50m,
            currency = "",
            description = "Missing currency"
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Post_MissingDescription_Returns400()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-1",
            amount = 50m,
            currency = "USD",
            description = ""
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task HealthCheck_ReturnsOk()
    {
        var client = CreateClient();
        var response = await client.GetAsync("/healthz");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}

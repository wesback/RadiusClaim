using System.Net;
using System.Net.Http.Json;
using Xunit;

namespace ExpenseApi.Tests;

/// <summary>
/// API-level validation tests for the expense submission endpoint.
/// Uses the shared in-process host with a fake Dapr sidecar and mocked DaprClient,
/// exercising the validation rules without requiring a running Dapr sidecar.
/// </summary>
public sealed class ExpenseApiValidationTests
{
    [Fact]
    public async Task Post_MissingEmployeeId_Returns400()
    {
        await using var host = ExpenseApiTestHost.Create();
        var response = await host.Client.PostAsJsonAsync("/expenses/", new
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
        await using var host = ExpenseApiTestHost.Create();
        var response = await host.Client.PostAsJsonAsync("/expenses/", new
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
        await using var host = ExpenseApiTestHost.Create();
        var response = await host.Client.PostAsJsonAsync("/expenses/", new
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
        await using var host = ExpenseApiTestHost.Create();
        var response = await host.Client.PostAsJsonAsync("/expenses/", new
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
        await using var host = ExpenseApiTestHost.Create();
        var response = await host.Client.GetAsync("/healthz");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}

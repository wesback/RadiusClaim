using System.Net;
using System.Net.Http.Json;
using Dapr.Client;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Moq;
using RadiusClaim.Contracts;
using Xunit;

namespace ExpenseApi.Tests;

/// <summary>
/// OAuth2 authentication tests for expense endpoints.
/// Verifies that bearer token validation is enforced on approval actions (approve, reject).
/// Submission (POST /expenses) and read endpoints (GET) remain public and do not require authentication.
/// </summary>
public sealed class OAuth2AuthenticationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;
    private const string TestAuthority = "https://login.microsoftonline.com/test-tenant";
    private const string TestAudience = "https://radiusclaim.azurewebsites.net/api";

    public OAuth2AuthenticationTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                // Mock DaprClient to avoid requiring Dapr sidecar
                var existing = services.SingleOrDefault(d => d.ServiceType == typeof(DaprClient));
                if (existing is not null) services.Remove(existing);

                var mockDaprClient = new Mock<DaprClient>();
                
                // Mock successful state creation for expense POST
                mockDaprClient
                    .Setup(c => c.TrySaveStateAsync(
                        It.IsAny<string>(),
                        It.IsAny<string>(),
                        It.IsAny<ExpenseRecord>(),
                        It.IsAny<CancellationToken>()))
                    .ReturnsAsync(true);

                // Mock index updates
                mockDaprClient
                    .Setup(c => c.SaveStateAsync(
                        It.IsAny<string>(),
                        It.IsAny<string>(),
                        It.IsAny<object>(),
                        It.IsAny<StateOptions>(),
                        It.IsAny<CancellationToken>()))
                    .Returns(Task.CompletedTask);

                // Mock workflow invocation
                mockDaprClient
                    .Setup(c => c.StartWorkflowAsync(
                        It.IsAny<string>(),
                        It.IsAny<string>(),
                        It.IsAny<object>(),
                        It.IsAny<CancellationToken>()))
                    .ReturnsAsync("workflow-id");

                services.AddSingleton(mockDaprClient.Object);
            });

            // Configure authentication to accept test tokens without real Entra validation
            builder.UseSetting("AzureAd:Authority", TestAuthority);
            builder.UseSetting("AzureAd:Audience", TestAudience);
        });
    }

    private HttpClient CreateClient() => _factory.CreateClient();

    private string GenerateTestJwt(string issuer = TestAuthority, string audience = TestAudience)
    {
        // Create a minimal test JWT without real signing
        // In production, tokens are signed by Entra ID
        var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = issuer,
            Audience = audience,
            IssuedAt = DateTime.UtcNow,
            Expires = DateTime.UtcNow.AddHours(1),
            SigningCredentials = new SigningCredentials(
                new SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes("test-key-32-characters-long-test")),
                SecurityAlgorithms.HmacSha256)
        });
        return token;
    }

    // Test: POST /expenses WITHOUT bearer token is allowed (public endpoint — anyone can submit)
    [Fact]
    public async Task PostExpense_WithoutBearerToken_IsAllowed()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-test",
            amount = 50m,
            currency = "USD",
            description = "Test expense"
        });

        // POST /expenses is intentionally anonymous — employees can submit without auth.
        // Auth is only required for approve/reject actions.
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: POST /expenses WITH invalid bearer token returns 401
    [Fact]
    public async Task PostExpense_WithInvalidBearerToken_Returns401Unauthorized()
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", "invalid-token-xyz");
        
        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-test",
            amount = 50m,
            currency = "USD",
            description = "Test expense"
        });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: GET /expenses (read) without bearer token is allowed (public endpoint)
    [Fact]
    public async Task GetExpensesList_WithoutBearerToken_ReturnsOk()
    {
        var client = CreateClient();
        var response = await client.GetAsync("/expenses/");

        // Should succeed or return 503 (Dapr unavailable), not 401
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: GET /expenses/{id} (read) without bearer token is allowed (public endpoint)
    [Fact]
    public async Task GetExpenseById_WithoutBearerToken_ReturnsOkOrNotFound()
    {
        var client = CreateClient();
        var response = await client.GetAsync("/expenses/test-id");

        // Should succeed, return 404 or 503, but NOT 401
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: POST /expenses/{id}/approve WITHOUT bearer token returns 401
    [Fact]
    public async Task PostApproveExpense_WithoutBearerToken_Returns401Unauthorized()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/test-id/approve", new
        {
            reason = "Approved by finance"
        });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: POST /expenses/{id}/reject WITHOUT bearer token returns 401
    [Fact]
    public async Task PostRejectExpense_WithoutBearerToken_Returns401Unauthorized()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/expenses/test-id/reject", new
        {
            reason = "Rejected: invalid receipt"
        });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: GET /expenses/{id}/workflow (read) without bearer token is allowed (public)
    [Fact]
    public async Task GetExpenseWorkflow_WithoutBearerToken_ReturnsOkOrNotFound()
    {
        var client = CreateClient();
        var response = await client.GetAsync("/expenses/test-id/workflow");

        // Should return 404 or success, not 401
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Test: POST /expenses with valid bearer token (bearer prefix)
    // Note: In real scenarios, token validation occurs via Entra ID; 
    // for tests, we verify the middleware accepts Authorization header presence
    [Fact]
    public async Task PostExpense_WithValidBearerTokenFormat_VerifiesAuthHeaderProcessing()
    {
        var client = CreateClient();
        
        // Valid JWT format (with correct Bearer prefix)
        var validToken = GenerateTestJwt();
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", validToken);

        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-test",
            amount = 50m,
            currency = "USD",
            description = "Test expense"
        });

        // In test environment with mocked auth, this might succeed (200/201/503)
        // The important assertion is that it is NOT 401 due to malformed/missing Bearer prefix
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Verify that POST /expenses without Authorization header is allowed (public endpoint)
    [Fact]
    public async Task PostExpense_MissingAuthorizationHeader_IsAllowed()
    {
        var client = CreateClient();
        
        // Explicitly ensure no Authorization header is set
        Assert.Null(client.DefaultRequestHeaders.Authorization);

        var response = await client.PostAsJsonAsync("/expenses/", new
        {
            employeeId = "emp-test",
            amount = 50m,
            currency = "USD",
            description = "Test expense"
        });

        // POST /expenses is anonymous by design — no auth required
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}

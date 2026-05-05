using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using Dapr.Workflow;
using Dapr.Workflow.Client;
using Dapr.Workflow.Serialization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Moq;
using RadiusClaim.Dapr;
using WorkflowEngine.Workflows;
using Xunit;

namespace WorkflowEngine.Tests;

public sealed class DecisionEndpointAnonymousTests
{
    [Fact]
    public async Task DecideEndpoint_WithAppApiTokenConfigured_DoesNotRequireDaprApiToken()
    {
        await using var host = WorkflowEngineTestHost.Create(appApiToken: "test-token");

        var response = await host.Client.PostAsJsonAsync("/workflows/manual-review-1/decide", new
        {
            approved = true
        });

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        host.WorkflowClientMock.Verify(client => client.RaiseEventAsync(
            "manual-review-1",
            ExpenseApprovalWorkflow.ManualDecisionEventName,
            It.IsAny<object>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    private sealed class WorkflowEngineTestHost : IAsyncDisposable
    {
        private readonly string? _previousAppApiToken;
        private readonly string? _previousDaprGrpcPort;
        private readonly WebApplicationFactory<Program> _factory;

        private WorkflowEngineTestHost(
            string? previousAppApiToken,
            string? previousDaprGrpcPort,
            FakeGrpcPortListener grpcPortListener,
            Mock<DaprWorkflowClient> workflowClientMock,
            WebApplicationFactory<Program> factory)
        {
            _previousAppApiToken = previousAppApiToken;
            _previousDaprGrpcPort = previousDaprGrpcPort;
            GrpcPortListener = grpcPortListener;
            WorkflowClientMock = workflowClientMock;
            _factory = factory;
            Client = _factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        }

        public HttpClient Client { get; }
        public FakeGrpcPortListener GrpcPortListener { get; }
        public Mock<DaprWorkflowClient> WorkflowClientMock { get; }

        public static WorkflowEngineTestHost Create(string? appApiToken)
        {
            var grpcPortListener = new FakeGrpcPortListener();
            var previousAppApiToken = Environment.GetEnvironmentVariable("APP_API_TOKEN");
            var previousDaprGrpcPort = Environment.GetEnvironmentVariable("DAPR_GRPC_PORT");

            Environment.SetEnvironmentVariable("APP_API_TOKEN", appApiToken);
            Environment.SetEnvironmentVariable("DAPR_GRPC_PORT", grpcPortListener.Port.ToString(CultureInfo.InvariantCulture));

            var workflowClientMock = new Mock<DaprWorkflowClient>(MockBehavior.Strict);
            workflowClientMock
                .Setup(client => client.GetWorkflowStateAsync(
                    It.IsAny<string>(),
                    It.IsAny<bool>(),
                    It.IsAny<CancellationToken>()))
                .ReturnsAsync((string instanceId, bool _, CancellationToken _) => CreateRunningState(instanceId));

            workflowClientMock
                .Setup(client => client.RaiseEventAsync(
                    It.IsAny<string>(),
                    It.IsAny<string>(),
                    It.IsAny<object>(),
                    It.IsAny<CancellationToken>()))
                .Returns(Task.CompletedTask);

            var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Development");
                builder.ConfigureServices(services =>
                {
                    services.RemoveAll<DaprWorkflowClient>();
                    services.AddSingleton(workflowClientMock.Object);
                });
            });

            return new WorkflowEngineTestHost(
                previousAppApiToken,
                previousDaprGrpcPort,
                grpcPortListener,
                workflowClientMock,
                factory);
        }

        public async ValueTask DisposeAsync()
        {
            Client.Dispose();
            _factory.Dispose();
            GrpcPortListener.Dispose();
            Environment.SetEnvironmentVariable("APP_API_TOKEN", _previousAppApiToken);
            Environment.SetEnvironmentVariable("DAPR_GRPC_PORT", _previousDaprGrpcPort);
            await Task.CompletedTask;
        }

        private static WorkflowState CreateRunningState(string instanceId)
        {
            var metadata = new WorkflowMetadata(
                instanceId,
                RadiusClaimDapr.Workflows.ExpenseApproval,
                WorkflowRuntimeStatus.Running,
                DateTime.UtcNow,
                DateTime.UtcNow,
                new JsonWorkflowSerializer());

            return new WorkflowState(metadata);
        }
    }

    private sealed class FakeGrpcPortListener : IDisposable
    {
        private readonly CancellationTokenSource _shutdown = new();
        private readonly TcpListener _listener;
        private readonly Task _acceptLoop;

        public FakeGrpcPortListener()
        {
            _listener = new TcpListener(IPAddress.Loopback, 0);
            _listener.Start();
            Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
            _acceptLoop = Task.Run(AcceptLoopAsync);
        }

        public int Port { get; }

        public void Dispose()
        {
            _shutdown.Cancel();
            _listener.Stop();

            try
            {
                _acceptLoop.GetAwaiter().GetResult();
            }
            catch
            {
                // Listener shutdown is expected during disposal.
            }
        }

        private async Task AcceptLoopAsync()
        {
            while (!_shutdown.IsCancellationRequested)
            {
                try
                {
                    using var socket = await _listener.AcceptSocketAsync(_shutdown.Token);
                    socket.Close();
                }
                catch when (_shutdown.IsCancellationRequested)
                {
                    break;
                }
                catch (ObjectDisposedException) when (_shutdown.IsCancellationRequested)
                {
                    break;
                }
            }
        }
    }
}

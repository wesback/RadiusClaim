using System.Net;
using System.Net.Sockets;
using System.Text;

namespace ExpenseApi.Tests;

internal sealed class FakeDaprSidecar : IDisposable
{
    private readonly HttpListener _listener;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Task _listenLoop;

    public FakeDaprSidecar()
    {
        Port = GetFreePort();
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://127.0.0.1:{Port}/");
        _listener.Prefixes.Add($"http://localhost:{Port}/");
        _listener.Start();
        _listenLoop = Task.Run(ListenAsync);
    }

    public int Port { get; }
    public HttpStatusCode WorkflowDecisionStatusCode { get; set; } = HttpStatusCode.Accepted;
    public HttpStatusCode WorkflowStartStatusCode { get; set; } = HttpStatusCode.Accepted;
    public int DecisionRequestCount { get; private set; }

    public void Dispose()
    {
        _shutdown.Cancel();
        try
        {
            _listener.Stop();
            _listener.Close();
        }
        catch
        {
        }

        try
        {
            _listenLoop.Wait(TimeSpan.FromSeconds(1));
        }
        catch
        {
            // Listener shutdown is expected during disposal.
        }
    }

    private async Task ListenAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            HttpListenerContext? context = null;

            try
            {
                context = await _listener.GetContextAsync();
            }
            catch when (_shutdown.IsCancellationRequested || !_listener.IsListening)
            {
                break;
            }

            if (context is not null)
            {
                await HandleAsync(context);
            }
        }
    }

    private async Task HandleAsync(HttpListenerContext context)
    {
        var path = context.Request.Url?.AbsolutePath ?? string.Empty;
        var statusCode = ResolveStatusCode(context.Request.HttpMethod, path);

        context.Response.StatusCode = (int)statusCode;
        context.Response.ContentType = "application/json";

        var payload = Encoding.UTF8.GetBytes($$"""{"status":{{(int)statusCode}}}""");
        context.Response.ContentLength64 = payload.Length;
        await context.Response.OutputStream.WriteAsync(payload);
        context.Response.Close();
    }

    private HttpStatusCode ResolveStatusCode(string method, string path)
    {
        if (method == HttpMethod.Get.Method &&
            string.Equals(path, "/v1.0/healthz/outbound", StringComparison.Ordinal))
        {
            return HttpStatusCode.OK;
        }

        if (method == HttpMethod.Post.Method &&
            string.Equals(path, "/v1.0/invoke/workflow-engine/method/workflows/start", StringComparison.Ordinal))
        {
            return WorkflowStartStatusCode;
        }

        if (method == HttpMethod.Post.Method &&
            path.StartsWith("/v1.0/invoke/workflow-engine/method/workflows/", StringComparison.Ordinal) &&
            path.EndsWith("/decide", StringComparison.Ordinal))
        {
            DecisionRequestCount++;
            return WorkflowDecisionStatusCode;
        }

        return HttpStatusCode.NotFound;
    }

    private static int GetFreePort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }
}

using System.Text.Json;
using RadiusClaim.Contracts;
using RadiusClaim.Dapr;
using Dapr;
using Dapr.Client;
using NotificationSvc.Templates;
using NotificationSvc.Transports;
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDaprClient();

var transportName = builder.Configuration["NOTIFICATION_TRANSPORT"] ?? "log";
if (transportName == "email")
    builder.Services.AddSingleton<INotificationTransport, EmailTransport>();
else
    builder.Services.AddSingleton<INotificationTransport, LoggingTransport>();

builder.Services.AddSingleton<ITemplateRenderer, TemplateRenderer>();

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
                    .AddService("notification-svc"))
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
            .AddService("notification-svc"));
});

var app = builder.Build();

app.UseCloudEvents();
app.MapSubscribeHandler();

app.MapGet("/", () => TypedResults.Ok(new ServiceDescriptor(
    RadiusClaimDapr.AppIds.NotificationService,
    "phase-5",
    [nameof(NotificationRequest)],
    ["pubsub"],
    "Pluggable transport: set NOTIFICATION_TRANSPORT=log (default) or NOTIFICATION_TRANSPORT=email")));

app.MapPost("/notifications",
    [Topic(RadiusClaimDapr.Components.PubSub, RadiusClaimDapr.Topics.ExpenseNotifications)]
    async (HttpRequest request, ILogger<Program> logger, CancellationToken cancellationToken) =>
    {
        var transport = request.HttpContext.RequestServices.GetRequiredService<INotificationTransport>();
        var renderer = request.HttpContext.RequestServices.GetRequiredService<ITemplateRenderer>();

        NotificationRequest? notification;

        try
        {
            notification = await request.ReadFromJsonAsync<NotificationRequest>(cancellationToken: cancellationToken);
        }
        catch (Exception ex) when (ex is JsonException or BadHttpRequestException or NotSupportedException)
        {
            logger.LogWarning(
                ex,
                "Ignoring malformed notification payload on topic {Topic}.",
                RadiusClaimDapr.Topics.ExpenseNotifications);

            return TypedResults.Ok(new { status = "ignored" });
        }

        if (notification is null || !IsValidNotification(notification))
        {
            logger.LogWarning(
                "Ignoring invalid notification payload on topic {Topic}.",
                RadiusClaimDapr.Topics.ExpenseNotifications);

            return TypedResults.Ok(new { status = "ignored" });
        }

        var renderedMessage = RenderMessage(renderer, notification, logger);
        var enrichedNotification = notification with { Message = renderedMessage };

        await transport.SendAsync(enrichedNotification, cancellationToken);

        // Return consistent anonymous type to keep lambda return type inference stable.
        return TypedResults.Ok(new { status = "delivered" });
    });

app.MapGet("/healthz", () => TypedResults.Ok(new { status = "ok" }));

app.Run();

static string RenderMessage(ITemplateRenderer renderer, NotificationRequest notification, ILogger logger)
{
    try
    {
        var templateName = TemplateRenderer.TemplateNameFor(notification.EventType);
        var variables = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = notification.ExpenseId,
            ["correlationId"] = notification.CorrelationId,
            ["recipient"]     = notification.Recipient,
            ["channel"]       = notification.Channel,
            ["eventType"]     = notification.EventType.ToString(),
            ["subject"]       = notification.Subject,
            ["message"]       = notification.Message,
            ["occurredAtUtc"] = notification.OccurredAtUtc.ToString("u"),
        };
        return renderer.Render(templateName, variables);
    }
    catch (Exception ex)
    {
        logger.LogWarning(ex, "Template rendering failed for event type {EventType}; falling back to original message.", notification.EventType);
        return notification.Message;
    }
}

static bool IsValidNotification(NotificationRequest? notification) =>
    notification is not null
    && !string.IsNullOrWhiteSpace(notification.ExpenseId)
    && !string.IsNullOrWhiteSpace(notification.CorrelationId)
    && !string.IsNullOrWhiteSpace(notification.Recipient)
    && !string.IsNullOrWhiteSpace(notification.Channel)
    && !string.IsNullOrWhiteSpace(notification.Subject)
    && !string.IsNullOrWhiteSpace(notification.Message)
    && notification.OccurredAtUtc != default;

internal sealed record ServiceDescriptor(
    string Service,
    string Phase,
    IReadOnlyList<string> Contracts,
    IReadOnlyList<string> DaprCapabilities,
    string NextStep);

public partial class Program;

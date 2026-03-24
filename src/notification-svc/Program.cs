using System.Text.Json;
using RadiusClaim.Contracts;
using Dapr;
using Dapr.Client;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDaprClient();

var app = builder.Build();

app.UseCloudEvents();
app.MapSubscribeHandler();

app.MapGet("/", () => TypedResults.Ok(new ServiceDescriptor(
    RadiusClaimDapr.AppIds.NotificationService,
    "phase-4",
    [nameof(NotificationRequest)],
    ["pubsub"],
    "Dapr pub/sub delivery is now visible via structured notification logs; transports stay deferred.")));

app.MapPost("/notifications",
    [Topic(RadiusClaimDapr.Components.PubSub, RadiusClaimDapr.Topics.ExpenseNotifications)]
    async (HttpRequest request, ILogger<Program> logger, CancellationToken cancellationToken) =>
    {
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

        logger.LogInformation(
            "Notification received: EventType={EventType}, ExpenseId={ExpenseId}, CorrelationId={CorrelationId}, Recipient={Recipient}, Subject={Subject}",
            notification.EventType,
            notification.ExpenseId,
            notification.CorrelationId,
            notification.Recipient,
            notification.Subject);

        return TypedResults.Ok(new { status = "received" });
    });

app.MapGet("/healthz", () => TypedResults.Ok(new { status = "ok" }));

app.Run();

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

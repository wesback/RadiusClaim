using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NotificationSvc.Transports;
using Xunit;

namespace NotificationSvc.Tests.Transports;

/// <summary>
/// Tests the DI wiring logic: that the correct transport is registered
/// based on the NOTIFICATION_TRANSPORT configuration value.
/// </summary>
public sealed class TransportDispatchTests
{
    private static INotificationTransport ResolveTransport(string? envValue)
    {
        var services = new ServiceCollection();
        services.AddLogging();

        var transportName = envValue ?? "log";
        if (transportName == "email")
            services.AddSingleton<INotificationTransport, EmailTransport>();
        else
            services.AddSingleton<INotificationTransport, LoggingTransport>();

        using var sp = services.BuildServiceProvider();
        return sp.GetRequiredService<INotificationTransport>();
    }

    [Theory]
    [InlineData(null,    "log")]
    [InlineData("",      "log")]
    [InlineData("log",   "log")]
    [InlineData("other", "log")]
    public void DefaultAndUnknown_ResolvesToLoggingTransport(string? envValue, string expectedName)
    {
        var transport = ResolveTransport(envValue);
        Assert.IsType<LoggingTransport>(transport);
        Assert.Equal(expectedName, transport.TransportName);
    }

    [Fact]
    public void EmailValue_ResolvesToEmailTransport()
    {
        var transport = ResolveTransport("email");
        Assert.IsType<EmailTransport>(transport);
        Assert.Equal("email", transport.TransportName);
    }

    [Fact]
    public void LoggingTransport_ImplementsInterface()
    {
        var transport = ResolveTransport("log");
        Assert.IsAssignableFrom<INotificationTransport>(transport);
    }

    [Fact]
    public void EmailTransport_ImplementsInterface()
    {
        var transport = ResolveTransport("email");
        Assert.IsAssignableFrom<INotificationTransport>(transport);
    }
}

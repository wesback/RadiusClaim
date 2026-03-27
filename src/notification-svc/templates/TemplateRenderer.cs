using System.Text.RegularExpressions;
using RadiusClaim.Contracts;

namespace NotificationSvc.Templates;

/// <summary>
/// Loads message templates that are embedded in the assembly and substitutes
/// <c>{{variable}}</c> placeholders (case-insensitive) from the supplied dictionary.
/// </summary>
public sealed partial class TemplateRenderer : ITemplateRenderer
{
    [GeneratedRegex(@"\{\{(\w+)\}\}", RegexOptions.IgnoreCase)]
    private static partial Regex PlaceholderPattern();

    public string Render(string templateName, IReadOnlyDictionary<string, string> variables)
    {
        var assembly = typeof(TemplateRenderer).Assembly;
        var resourceName = $"NotificationSvc.templates.{templateName}.txt";

        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException(
                $"Notification template '{templateName}' not found. " +
                $"Expected embedded resource '{resourceName}'.");

        using var reader = new StreamReader(stream);
        var template = reader.ReadToEnd();

        return PlaceholderPattern().Replace(template, match =>
        {
            var key = match.Groups[1].Value;
            return variables.TryGetValue(key, out var value) ? value : string.Empty;
        });
    }

    /// <summary>
    /// Maps a <see cref="NotificationEventType"/> to its template name.
    /// </summary>
    public static string TemplateNameFor(NotificationEventType eventType) =>
        eventType switch
        {
            NotificationEventType.ExpenseSubmitted       => "expense-submitted",
            NotificationEventType.ExpenseApproved        => "expense-approved",
            NotificationEventType.ExpenseRejected        => "expense-rejected",
            NotificationEventType.ApprovalTimeout        => "approval-timeout",
            NotificationEventType.ExpenseRejectedTimeout => "expense-rejected-timeout",
            NotificationEventType.ManualReviewRequested  => "approval-timeout",
            _ => throw new ArgumentOutOfRangeException(nameof(eventType), eventType, "No template registered for event type.")
        };
}

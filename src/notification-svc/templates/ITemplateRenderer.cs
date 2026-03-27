namespace NotificationSvc.Templates;

/// <summary>
/// Renders a named template by substituting {{variable}} placeholders with provided values.
/// </summary>
public interface ITemplateRenderer
{
    /// <summary>
    /// Renders the template identified by <paramref name="templateName"/> using the supplied
    /// <paramref name="variables"/> dictionary.  Unknown placeholders are replaced with an
    /// empty string.
    /// </summary>
    string Render(string templateName, IReadOnlyDictionary<string, string> variables);
}

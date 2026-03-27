using NotificationSvc.Templates;
using RadiusClaim.Contracts;
using Xunit;

namespace NotificationSvc.Tests.Templates;

public sealed class TemplateRendererTests
{
    private readonly TemplateRenderer _renderer = new();

    [Theory]
    [InlineData(NotificationEventType.ExpenseSubmitted,       "expense-submitted")]
    [InlineData(NotificationEventType.ExpenseApproved,        "expense-approved")]
    [InlineData(NotificationEventType.ExpenseRejected,        "expense-rejected")]
    [InlineData(NotificationEventType.ApprovalTimeout,        "approval-timeout")]
    [InlineData(NotificationEventType.ExpenseRejectedTimeout, "expense-rejected-timeout")]
    [InlineData(NotificationEventType.ManualReviewRequested,  "approval-timeout")]
    public void TemplateNameFor_ReturnsExpectedName(NotificationEventType eventType, string expected) =>
        Assert.Equal(expected, TemplateRenderer.TemplateNameFor(eventType));

    [Fact]
    public void Render_ExpenseSubmitted_SubstitutesAllVariables()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = "EXP-001",
            ["submitter"]     = "alice@contoso.com",
            ["subject"]       = "Team offsite",
            ["occurredAtUtc"] = "2026-03-27 10:00:00Z",
        };

        var result = _renderer.Render("expense-submitted", vars);

        Assert.Contains("EXP-001", result);
        Assert.Contains("alice@contoso.com", result);
        Assert.Contains("Team offsite", result);
        Assert.Contains("2026-03-27 10:00:00Z", result);
        Assert.DoesNotContain("{{", result);
    }

    [Fact]
    public void Render_ExpenseApproved_SubstitutesAllVariables()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = "EXP-002",
            ["approver"]      = "bob@contoso.com",
            ["amount"]        = "450.00",
            ["subject"]       = "Conference registration",
            ["occurredAtUtc"] = "2026-03-27 11:00:00Z",
        };

        var result = _renderer.Render("expense-approved", vars);

        Assert.Contains("EXP-002", result);
        Assert.Contains("bob@contoso.com", result);
        Assert.Contains("450.00", result);
        Assert.Contains("Conference registration", result);
        Assert.DoesNotContain("{{", result);
    }

    [Fact]
    public void Render_ExpenseRejected_SubstitutesAllVariables()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = "EXP-003",
            ["reason"]        = "Missing receipts",
            ["approver"]      = "carol@contoso.com",
            ["subject"]       = "Travel reimbursement",
            ["occurredAtUtc"] = "2026-03-27 12:00:00Z",
        };

        var result = _renderer.Render("expense-rejected", vars);

        Assert.Contains("EXP-003", result);
        Assert.Contains("Missing receipts", result);
        Assert.Contains("carol@contoso.com", result);
        Assert.DoesNotContain("{{", result);
    }

    [Fact]
    public void Render_ApprovalTimeout_SubstitutesAllVariables()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = "EXP-004",
            ["submitter"]     = "dave@contoso.com",
            ["subject"]       = "Equipment purchase",
            ["occurredAtUtc"] = "2026-03-27 13:00:00Z",
        };

        var result = _renderer.Render("approval-timeout", vars);

        Assert.Contains("EXP-004", result);
        Assert.Contains("dave@contoso.com", result);
        Assert.DoesNotContain("{{", result);
    }

    [Fact]
    public void Render_ExpenseRejectedTimeout_SubstitutesAllVariables()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = "EXP-005",
            ["subject"]       = "Software license",
            ["occurredAtUtc"] = "2026-03-27 14:00:00Z",
        };

        var result = _renderer.Render("expense-rejected-timeout", vars);

        Assert.Contains("EXP-005", result);
        Assert.Contains("Software license", result);
        Assert.DoesNotContain("{{", result);
    }

    [Fact]
    public void Render_UnknownPlaceholder_ReplacedWithEmpty()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["expenseId"]     = "EXP-006",
            ["subject"]       = "Lunch",
            ["occurredAtUtc"] = "2026-03-27 14:00:00Z",
        };

        var result = _renderer.Render("approval-timeout", vars);

        Assert.Contains("EXP-006", result);
        Assert.DoesNotContain("{{submitter}}", result);
    }

    [Fact]
    public void Render_PlaceholderMatchingIsCaseInsensitive()
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["EXPENSEID"]     = "EXP-007",
            ["SUBJECT"]       = "Taxi",
            ["OCCURREDATUTC"] = "2026-03-27 15:00:00Z",
        };

        var result = _renderer.Render("expense-rejected-timeout", vars);

        Assert.Contains("EXP-007", result);
        Assert.Contains("Taxi", result);
    }

    [Fact]
    public void Render_MissingTemplate_ThrowsInvalidOperationException()
    {
        var vars = new Dictionary<string, string>();
        Assert.Throws<InvalidOperationException>(() => _renderer.Render("nonexistent-template", vars));
    }
}

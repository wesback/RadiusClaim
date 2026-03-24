using System.Text.Json.Serialization;

namespace RadiusClaim.Contracts;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ExpenseStatus
{
    Submitted,
    ManualReviewRequested,
    Approved,
    Rejected,
    Reimbursed
}

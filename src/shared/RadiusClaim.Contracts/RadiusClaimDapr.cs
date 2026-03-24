namespace RadiusClaim.Contracts;

public static class RadiusClaimDapr
{
    public static class AppIds
    {
        public const string ExpenseApi = "expense-api";
        public const string WorkflowEngine = "workflow-engine";
        public const string NotificationService = "notification-svc";
    }

    public static class Components
    {
        public const string StateStore = "statestore";
        public const string PubSub = "pubsub";
    }

    public static class StateKeys
    {
        public const string ExpensePrefix = "expense:";
        public const string ExpenseIndex = "expense-index";

        public static string Expense(string expenseId) => $"{ExpensePrefix}{expenseId}";
    }

    public static class Topics
    {
        public const string ExpenseNotifications = "expense-notifications";
    }

    public static class Workflows
    {
        public const string ExpenseApproval = "ExpenseApprovalWorkflow";
    }
}

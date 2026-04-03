namespace RadiusClaim.Dapr;

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
        public const string PersistentStore = "statestore";
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

    public static class WorkflowEvents
    {
        /// <summary>Event name raised by approve/reject API endpoints to resume a paused workflow.</summary>
        public const string ExpenseDecision = "expense-decision";
    }
}

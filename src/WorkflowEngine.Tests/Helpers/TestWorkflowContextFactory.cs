using Dapr.Workflow;
using Moq;

namespace WorkflowEngine.Tests.Helpers;

internal static class TestWorkflowContextFactory
{
    internal static WorkflowActivityContext Create(string instanceId = "test-instance-id")
    {
        var mock = new Mock<WorkflowActivityContext>();
        mock.Setup(c => c.InstanceId).Returns(instanceId);
        return mock.Object;
    }
}

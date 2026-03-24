FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

COPY CloudExpenseLite.slnx ./
COPY global.json ./
COPY src/notification-svc/NotificationSvc.csproj src/notification-svc/
COPY src/expense-api/ExpenseApi.csproj src/expense-api/
COPY src/workflow-engine/WorkflowEngine.csproj src/workflow-engine/
COPY src/shared/CloudExpense.Contracts/CloudExpense.Contracts.csproj src/shared/CloudExpense.Contracts/
RUN dotnet restore src/notification-svc/NotificationSvc.csproj --nologo

COPY src ./src
RUN dotnet publish src/notification-svc/NotificationSvc.csproj -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false --nologo

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "NotificationSvc.dll"]

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["Directory.Build.props", "./"]
COPY ["src/BuildingBlocks/", "./src/BuildingBlocks/"]
COPY ["src/Workers/FlightsPlatform.AnalyticsWorker/", "./src/Workers/FlightsPlatform.AnalyticsWorker/"]

RUN dotnet restore "src/Workers/FlightsPlatform.AnalyticsWorker/FlightsPlatform.AnalyticsWorker.csproj"
RUN dotnet publish "src/Workers/FlightsPlatform.AnalyticsWorker/FlightsPlatform.AnalyticsWorker.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "FlightsPlatform.AnalyticsWorker.dll"]
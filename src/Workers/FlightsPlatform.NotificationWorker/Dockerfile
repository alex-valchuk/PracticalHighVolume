FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy solution-wide props and all sources needed for the build.
COPY ["Directory.Build.props", "./"]
COPY ["src/BuildingBlocks/", "./src/BuildingBlocks/"]
COPY ["src/Workers/FlightsPlatform.NotificationWorker/", "./src/Workers/FlightsPlatform.NotificationWorker/"]

RUN dotnet restore "src/Workers/FlightsPlatform.NotificationWorker/FlightsPlatform.NotificationWorker.csproj"
RUN dotnet publish "src/Workers/FlightsPlatform.NotificationWorker/FlightsPlatform.NotificationWorker.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "FlightsPlatform.NotificationWorker.dll"]
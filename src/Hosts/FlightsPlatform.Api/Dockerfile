FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["Directory.Build.props", "./"]
COPY ["src/BuildingBlocks/", "./src/BuildingBlocks/"]
COPY ["src/Modules/", "./src/Modules/"]
COPY ["src/Hosts/FlightsPlatform.Api/", "./src/Hosts/FlightsPlatform.Api/"]

RUN dotnet restore "src/Hosts/FlightsPlatform.Api/FlightsPlatform.Api.csproj"
RUN dotnet publish "src/Hosts/FlightsPlatform.Api/FlightsPlatform.Api.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "FlightsPlatform.Api.dll"]
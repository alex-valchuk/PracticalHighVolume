#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-File {
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [string] $Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $full = Join-Path (Get-Location).Path $Path
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path)
}

function Invoke-PsqlScalar {
    param([string] $Sql)
    $result = docker exec flights-postgres psql -U flights -d flights_demo -tAc $Sql 2>$null
    if ($null -eq $result) { return "" }
    return ($result | Out-String).Trim()
}

Write-Host ""
Write-Host "=== Fix: per-schema migration history for FlightCatalog ==="
Write-Host ""

# --- 1. Check container ---
$running = docker ps --filter "name=flights-postgres" --format "{{.Names}}"
if ($running -ne "flights-postgres") {
    Write-Host "container flights-postgres is not running. Start it and retry." -ForegroundColor Red
    exit 1
}
Write-Host "  OK container flights-postgres"

# --- 2. Check current state ---
Write-Host ""
Write-Host "=== Current state ==="

$inPublic        = Invoke-PsqlScalar "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='__EFMigrationsHistory';"
$inFlightCatalog = Invoke-PsqlScalar "SELECT 1 FROM information_schema.tables WHERE table_schema='flight_catalog' AND table_name='__EFMigrationsHistory';"

Write-Host ("  public.__EFMigrationsHistory        : " + $(if ($inPublic -eq "1") { "EXISTS" } else { "absent" }))
Write-Host ("  flight_catalog.__EFMigrationsHistory: " + $(if ($inFlightCatalog -eq "1") { "EXISTS" } else { "absent" }))

# --- 3. Move if needed ---
Write-Host ""
Write-Host "=== Move table ==="

if ($inPublic -eq "1" -and $inFlightCatalog -ne "1") {
    docker exec flights-postgres psql -U flights -d flights_demo -c "ALTER TABLE public.""__EFMigrationsHistory"" SET SCHEMA flight_catalog;" | Out-Null
    Write-Host "  + moved public.__EFMigrationsHistory -> flight_catalog.__EFMigrationsHistory"
}
elseif ($inFlightCatalog -eq "1") {
    Write-Host "  already in flight_catalog - nothing to move"
}
else {
    Write-Host "  no history table found - nothing to move"
}

# --- 4. Patch FlightCatalog Infrastructure ---
Write-Host ""
Write-Host "=== Patch FlightCatalog.Infrastructure ==="

$diPath = "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/DependencyInjection.cs"

Write-File $diPath @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Infrastructure.BackgroundServices;
using FlightCatalog.Infrastructure.Integration.Bookings;
using FlightCatalog.Infrastructure.Persistence;
using FlightCatalog.Infrastructure.Persistence.Repositories;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FlightCatalog.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddFlightCatalogInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var ownConnection = configuration.GetConnectionString("FlightCatalog")
            ?? throw new InvalidOperationException("Connection string 'FlightCatalog' is not configured.");

        var externalConnection = configuration.GetConnectionString("BookingsSource")
            ?? throw new InvalidOperationException("Connection string 'BookingsSource' is not configured.");

        services.AddDbContext<FlightCatalogDbContext>(opts =>
            opts.UseNpgsql(ownConnection, npgsql =>
                npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "flight_catalog")));

        services.AddSingleton<NpgsqlDataSource>(sp => NpgsqlDataSource.Create(ownConnection));

        services.AddKeyedSingleton<NpgsqlDataSource>("bookings",
            (sp, key) => NpgsqlDataSource.Create(externalConnection));

        services.AddScoped<IFlightRepository, FlightRepository>();
        services.AddScoped<IFlightReadRepository, FlightReadRepository>();
        services.AddScoped<IAirportRepository, AirportRepository>();
        services.AddScoped<IAirportReadRepository, AirportReadRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        services.AddScoped<IBookingsSourceReader>(sp =>
        {
            var ds = sp.GetRequiredKeyedService<NpgsqlDataSource>("bookings");
            return new BookingsSourceReader(ds);
        });

        services.Configure<AirportSyncOptions>(configuration.GetSection(AirportSyncOptions.SectionName));
        services.AddHostedService<AirportSyncBackgroundService>();

        return services;
    }
}
'@

$factoryPath = "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Persistence/DesignTimeDbContextFactory.cs"

Write-File $factoryPath @'
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FlightCatalog.Infrastructure.Persistence;

internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<FlightCatalogDbContext>
{
    public FlightCatalogDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("FLIGHTS_CATALOG_CONNECTION")
            ?? "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

        var optionsBuilder = new DbContextOptionsBuilder<FlightCatalogDbContext>();
        optionsBuilder.UseNpgsql(connectionString, npgsql =>
            npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "flight_catalog"));

        return new FlightCatalogDbContext(optionsBuilder.Options);
    }
}
'@

# --- 5. Clean + build ---
Write-Host ""
Write-Host "=== Clean + build ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

# --- 6. Verify ---
Write-Host ""
Write-Host "=== Final check ==="

Write-Host ""
Write-Host "public schema tables:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;"

Write-Host "flight_catalog.__EFMigrationsHistory:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT ""MigrationId"" FROM flight_catalog.""__EFMigrationsHistory"" ORDER BY ""MigrationId"";"

Write-Host "booking.__EFMigrationsHistory:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT ""MigrationId"" FROM booking.""__EFMigrationsHistory"" ORDER BY ""MigrationId"";"

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(flight-catalog): move migration history to flight_catalog schema"'
Write-Host "  git push"
Write-Host ""
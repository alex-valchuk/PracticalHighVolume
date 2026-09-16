#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-SourceFile {
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

$infra   = "src/Modules/FlightCatalog/FlightCatalog.Infrastructure"
$hostDir = "src/Hosts/FlightsPlatform.Api"

Write-Host ""
Write-Host "=== Phase 2 FIX: introduce EF Core Migrations ==="
Write-Host ""

# ---------------------------------------------------------------------------
# 1. DesignTimeDbContextFactory — so ef tool can create DbContext without host
# ---------------------------------------------------------------------------
Write-Host "=== 1. DesignTimeDbContextFactory ==="

Write-SourceFile "$infra/Persistence/DesignTimeDbContextFactory.cs" @'
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FlightCatalog.Infrastructure.Persistence;

/// <summary>
/// Used ONLY by `dotnet ef` at design time (migration generation).
/// Not used at runtime — the host builds DbContext through DI.
/// </summary>
internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<FlightCatalogDbContext>
{
    public FlightCatalogDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("FLIGHTS_CATALOG_CONNECTION")
            ?? "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

        var optionsBuilder = new DbContextOptionsBuilder<FlightCatalogDbContext>();
        optionsBuilder.UseNpgsql(connectionString);

        return new FlightCatalogDbContext(optionsBuilder.Options);
    }
}
'@

# ---------------------------------------------------------------------------
# 2. Program.cs — replace EnsureCreatedAsync with MigrateAsync
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 2. Program.cs: MigrateAsync instead of EnsureCreatedAsync ==="

Write-SourceFile "$hostDir/Program.cs" @'
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;
using FlightsPlatform.SharedKernel;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

builder.Services.AddFlightCatalogApplication();
builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseExceptionHandler(errApp => errApp.Run(async ctx =>
{
    var feature = ctx.Features.Get<IExceptionHandlerFeature>();
    var ex = feature?.Error;

    var (status, payload) = ex switch
    {
        ValidationException ve => (StatusCodes.Status400BadRequest,
            (object)new
            {
                error = "validation_failed",
                details = ve.Errors.Select(e => e.ErrorMessage)
            }),
        DomainException de => (StatusCodes.Status400BadRequest,
            new { error = "domain_error", message = de.Message }),
        _ => (StatusCodes.Status500InternalServerError,
            new { error = "internal_error" })
    };

    ctx.Response.StatusCode = status;
    await ctx.Response.WriteAsJsonAsync(payload);
}));

app.UseHttpsRedirection();
app.MapControllers();
app.MapFlightCatalogEndpoints();
app.MapAirportEndpoints();

// Apply migrations at startup.
// NOTE: convenient for local development. In production, migrations
// are applied by CI/CD with a dedicated role that has DDL rights.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await db.Database.MigrateAsync();
}

app.Run();
'@

# ---------------------------------------------------------------------------
# 3. Ensure EF Core Design package present in Infrastructure.csproj
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 3. Infrastructure csproj: ensure Design package ==="

$infraCsprojPath = Join-Path (Get-Location).Path "$infra/FlightCatalog.Infrastructure.csproj"
$csproj = [System.IO.File]::ReadAllText($infraCsprojPath)

if ($csproj -notmatch 'Microsoft\.EntityFrameworkCore\.Design') {
    $designPackage = '    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="9.0.0">' + "`r`n" +
                     '      <PrivateAssets>all</PrivateAssets>' + "`r`n" +
                     '    </PackageReference>' + "`r`n"
    $csproj = $csproj -replace '(<ItemGroup>)', ("`$1`r`n" + $designPackage)
    [System.IO.File]::WriteAllText($infraCsprojPath, $csproj, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + added Microsoft.EntityFrameworkCore.Design"
} else {
    Write-Host "  - Design package already present"
}

# ---------------------------------------------------------------------------
# 4. Install local dotnet-ef tool
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 4. Install dotnet-ef tool ==="

if (-not (Test-Path ".config/dotnet-tools.json")) {
    dotnet new tool-manifest | Out-Null
    Write-Host "  + created .config/dotnet-tools.json"
}

dotnet tool install dotnet-ef --version 9.0.0 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    dotnet tool update dotnet-ef --version 9.0.0 | Out-Null
}
dotnet tool restore | Out-Null
Write-Host "  + dotnet-ef ready"

# ---------------------------------------------------------------------------
# 5. Drop flight_catalog schema so migrations start from clean slate
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 5. Drop flight_catalog schema (flights_demo) ==="

$container = "flights-postgres"
$running = docker ps --filter "name=$container" --format "{{.Names}}"
if ($running -ne $container) {
    Write-Host "  container '$container' is not running - skipping DROP" -ForegroundColor Yellow
    Write-Host "  start it manually, then run: dotnet ef database update ..." -ForegroundColor Yellow
} else {
    docker exec $container psql -U flights -d flights_demo -c "DROP SCHEMA IF EXISTS flight_catalog CASCADE;" | Out-Null
    Write-Host "  + dropped schema flight_catalog in flights_demo"
}

# ---------------------------------------------------------------------------
# 6. Clean + build
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 6. Clean + build ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED - see errors above" -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

# ---------------------------------------------------------------------------
# 7. Generate InitialCreate migration
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 7. Generate InitialCreate migration ==="

$migrationsDir = "$infra/Persistence/Migrations"
if (Test-Path -LiteralPath $migrationsDir) {
    Remove-Item -LiteralPath $migrationsDir -Recurse -Force
    Write-Host "  - removed existing Migrations folder"
}

dotnet ef migrations add InitialCreate `
    --project "$infra/FlightCatalog.Infrastructure.csproj" `
    --output-dir "Persistence/Migrations"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "MIGRATION GENERATION FAILED" -ForegroundColor Red
    exit 1
}

Write-Host "  + InitialCreate migration generated"

# ---------------------------------------------------------------------------
# 8. Apply migration
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 8. Apply migration to flights_demo ==="

$env:FLIGHTS_CATALOG_CONNECTION = "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"

dotnet ef database update `
    --project "$infra/FlightCatalog.Infrastructure.csproj"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "MIGRATION APPLY FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "SUCCESS." -ForegroundColor Green
Write-Host ""
Write-Host "What happened:" -ForegroundColor Yellow
Write-Host "  1. DesignTimeDbContextFactory added (for dotnet-ef)"
Write-Host "  2. Program.cs now uses MigrateAsync instead of EnsureCreatedAsync"
Write-Host "  3. dotnet-ef installed as local tool (.config/dotnet-tools.json)"
Write-Host "  4. Dropped old flight_catalog schema"
Write-Host "  5. InitialCreate migration generated in Persistence/Migrations/"
Write-Host "  6. Migration applied to flights_demo"
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  Watch for airport sync on startup, then check:"
Write-Host "    GET /flight-catalog/airports/SVO"
Write-Host "    POST /flight-catalog/airports/sync"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "Phase 2: ACL + airport sync + EF Core Migrations"'
Write-Host ""
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

Write-Host ""
Write-Host "=== Add backend endpoints: /health, /dashboard/summary, CORS ==="
Write-Host ""

$hostDir = "src/Hosts/FlightsPlatform.Api"

# ===========================================================================
# 1. DashboardEndpoints.cs
# ===========================================================================
Write-Host "=== 1. DashboardEndpoints ==="

Write-File "$hostDir/Endpoints/DashboardEndpoints.cs" @'
using Bookings.Domain;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;

namespace FlightsPlatform.Api.Endpoints;

public static class DashboardEndpoints
{
    public static IEndpointRouteBuilder MapDashboardEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/dashboard/summary", async (
            FlightCatalogDbContext fcDb,
            BookingDbContext bkDb,
            CancellationToken ct) =>
        {
            var flights = await fcDb.Flights.CountAsync(ct);
            var airports = await fcDb.Airports.CountAsync(ct);
            var bookings = await bkDb.Bookings.CountAsync(ct);
            var activeBookings = await bkDb.Bookings
                .CountAsync(b => b.Status == BookingStatus.Pending, ct);

            return Results.Ok(new
            {
                flights,
                airports,
                bookings,
                activeBookings
            });
        })
        .WithTags("Dashboard")
        .WithName("GetDashboardSummary");

        return app;
    }
}
'@

# ===========================================================================
# 2. Program.cs (with CORS, /health, /dashboard/summary)
# ===========================================================================
Write-Host ""
Write-Host "=== 2. Program.cs ==="

Write-File "$hostDir/Program.cs" @'
using Bookings.Api;
using Bookings.Application;
using Bookings.Infrastructure;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FlightsPlatform.Api.Endpoints;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;
using FlightsPlatform.SharedKernel;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// CORS for Angular dev server (Development only).
builder.Services.AddCors(options =>
{
    options.AddPolicy("frontend", policy =>
    {
        policy.WithOrigins("http://localhost:4200")
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

builder.Services.AddFlightCatalogApplication();
builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

builder.Services.AddBookingsApplication();
builder.Services.AddBookingsInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
    app.UseCors("frontend");
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
app.MapBookingsEndpoints();
app.MapDashboardEndpoints();

// Health endpoint for the SPA header indicator.
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    time = DateTimeOffset.UtcNow
}))
.WithTags("Health")
.WithName("GetHealth");

using (var scope = app.Services.CreateScope())
{
    var fcDb = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await fcDb.Database.MigrateAsync();

    var bkDb = scope.ServiceProvider.GetRequiredService<BookingDbContext>();
    await bkDb.Database.MigrateAsync();
}

app.Run();
'@

# ===========================================================================
# 3. Build
# ===========================================================================
Write-Host ""
Write-Host "=== 3. Build backend ==="

dotnet build

if ($LASTEXITCODE -ne 0) {
    Write-Host "  BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED" -ForegroundColor Green

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Restart the API (Ctrl+C in the terminal, then):" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""
Write-Host "Verify in the browser:" -ForegroundColor Yellow
Write-Host "  https://localhost:50943/health"
Write-Host "     -> { ""status"": ""ok"", ""time"": ""..."" }"
Write-Host ""
Write-Host "  https://localhost:50943/dashboard/summary"
Write-Host "     -> { ""flights"": 0, ""airports"": N, ""bookings"": M, ""activeBookings"": K }"
Write-Host ""
Write-Host "Then refresh http://localhost:4200 - the header should turn green." -ForegroundColor Yellow
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(api): /health and /dashboard/summary endpoints + dev CORS"'
Write-Host "  git push"
Write-Host ""
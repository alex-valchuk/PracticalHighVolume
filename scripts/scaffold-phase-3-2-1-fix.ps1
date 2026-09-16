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
Write-Host "=== Fix for SPEC-003.2 script 3.2.1 ==="
Write-Host "Creating missing IFlightCatalogClient + FlightSummary"
Write-Host ""

Write-File "src/Modules/Bookings/Bookings.Application/Abstractions/IFlightCatalogClient.cs" @'
namespace Bookings.Application.Abstractions;

/// <summary>
/// Contract for synchronous queries to the FlightCatalog module.
/// Implementation lives in Bookings.Infrastructure and calls FlightCatalog
/// via IMediator. Declared here so that Bookings.Application does not
/// reference FlightCatalog.Application directly.
/// </summary>
public interface IFlightCatalogClient
{
    Task<FlightSummary?> GetFlightAsync(Guid flightId, CancellationToken ct = default);
}

public sealed record FlightSummary(
    Guid Id,
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset ScheduledDeparture,
    DateTimeOffset ScheduledArrival,
    int Status);
'@

Write-Host ""
Write-Host "=== Clean + build ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED - see errors above." -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

Write-Host ""
Write-Host "=== dotnet test ==="
dotnet test --no-build --nologo

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(bookings): phase 3.2.1 - AddTicket + IFlightCatalogClient"'
Write-Host "  git push"
Write-Host ""
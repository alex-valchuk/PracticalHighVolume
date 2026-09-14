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

Write-Host ""
Write-Host "=== Fix: EF Core-compatible Value Objects ==="
Write-Host ""

$base = "src/Modules/FlightCatalog/FlightCatalog.Domain/ValueObjects"

# AirportCode
Write-SourceFile "$base/AirportCode.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class AirportCode : ValueObject
{
    public string Value { get; private set; } = default!;

    private AirportCode() { }

    private AirportCode(string value) => Value = value;

    public static AirportCode Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Airport code cannot be empty");

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length != 3 || !normalized.All(char.IsLetter))
            throw new DomainException("Airport code must be exactly 3 letters. Got: " + value);

        return new AirportCode(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
'@

# FlightNumber
Write-SourceFile "$base/FlightNumber.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class FlightNumber : ValueObject
{
    public string Value { get; private set; } = default!;

    private FlightNumber() { }

    private FlightNumber(string value) => Value = value;

    public static FlightNumber Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Flight number cannot be empty");

        var normalized = value.Trim().ToUpperInvariant();
        var parts = normalized.Split('-');

        if (parts.Length != 2
            || parts[0].Length != 2 || !parts[0].All(char.IsLetter)
            || parts[1].Length < 1 || parts[1].Length > 4 || !parts[1].All(char.IsDigit))
        {
            throw new DomainException("Invalid flight number " + value + ". Expected format XX-NNNN.");
        }

        return new FlightNumber(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
'@

# Route
Write-SourceFile "$base/Route.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Route : ValueObject
{
    public AirportCode Departure { get; private set; } = default!;
    public AirportCode Arrival { get; private set; } = default!;

    private Route() { }

    private Route(AirportCode departure, AirportCode arrival)
    {
        Departure = departure;
        Arrival = arrival;
    }

    public static Route Create(AirportCode departure, AirportCode arrival)
    {
        if (departure == arrival)
            throw new DomainException("Departure and arrival airports must be different.");

        return new Route(departure, arrival);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Departure;
        yield return Arrival;
    }
}
'@

# Schedule
Write-SourceFile "$base/Schedule.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Schedule : ValueObject
{
    public DateTimeOffset Departure { get; private set; }
    public DateTimeOffset Arrival { get; private set; }

    private Schedule() { }

    private Schedule(DateTimeOffset departure, DateTimeOffset arrival)
    {
        Departure = departure;
        Arrival = arrival;
    }

    public static Schedule Create(DateTimeOffset departure, DateTimeOffset arrival)
    {
        if (arrival <= departure)
            throw new DomainException("Arrival must be after departure.");

        return new Schedule(departure, arrival);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Departure;
        yield return Arrival;
    }
}
'@

# Money
Write-SourceFile "$base/Money.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Money : ValueObject
{
    public decimal Amount { get; private set; }
    public string Currency { get; private set; } = default!;

    private Money() { }

    private Money(decimal amount, string currency)
    {
        Amount = amount;
        Currency = currency;
    }

    public static Money Create(decimal amount, string currency)
    {
        if (amount < 0)
            throw new DomainException("Amount cannot be negative.");

        if (string.IsNullOrWhiteSpace(currency) || currency.Length != 3)
            throw new DomainException("Currency must be a 3-letter ISO code.");

        return new Money(decimal.Round(amount, 2), currency.ToUpperInvariant());
    }

    public static Money Zero(string currency) => Create(0m, currency);

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Amount;
        yield return Currency;
    }

    public override string ToString() => Amount.ToString("0.00") + " " + Currency;
}
'@

Write-Host ""
Write-Host "=== Clean + build ==="
Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet build

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "BUILD SUCCEEDED" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "BUILD FAILED - send me the first errors" -ForegroundColor Red
}
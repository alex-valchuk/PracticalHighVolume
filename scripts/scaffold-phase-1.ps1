#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
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
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.Encoding]::ASCII)
    Write-Host ("  + " + $Path)
}

# ---------------------------------------------------------------------------
# Pre-flight check
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Phase 1 scaffold ==="
Write-Host ("Working directory: " + (Get-Location).Path)
Write-Host ""

if (-not (Test-Path -LiteralPath "src") -and -not (Test-Path -LiteralPath "*.slnx")) {
    Write-Host "WARNING: no 'src' folder and no .slnx here." -ForegroundColor Yellow
    Write-Host "Make sure you run this from the project root." -ForegroundColor Yellow
    $answer = Read-Host "Continue anyway? (y/N)"
    if ($answer -ne "y") { exit 1 }
}

# ---------------------------------------------------------------------------
# Directory.Build.props
# ---------------------------------------------------------------------------
Write-Host "=== Root config ==="
Write-SourceFile "Directory.Build.props" @'
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <GenerateDocumentationFile>false</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
'@

# ---------------------------------------------------------------------------
# csproj files
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== csproj files ==="

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.SharedKernel/FlightsPlatform.SharedKernel.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightsPlatform.SharedKernel</RootNamespace>
  </PropertyGroup>
</Project>
'@

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.Application.Abstractions/FlightsPlatform.Application.Abstractions.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightsPlatform.Application.Abstractions</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="FluentValidation" Version="11.10.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightsPlatform.SharedKernel\FlightsPlatform.SharedKernel.csproj" />
  </ItemGroup>
</Project>
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/FlightCatalog.Domain.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightCatalog.Domain</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\..\BuildingBlocks\FlightsPlatform.SharedKernel\FlightsPlatform.SharedKernel.csproj" />
  </ItemGroup>
</Project>
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/FlightCatalog.Application.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightCatalog.Application</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="FluentValidation" Version="11.10.0" />
    <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.10.0" />
    <PackageReference Include="Dapper" Version="2.1.35" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Domain\FlightCatalog.Domain.csproj" />
    <ProjectReference Include="..\..\..\BuildingBlocks\FlightsPlatform.Application.Abstractions\FlightsPlatform.Application.Abstractions.csproj" />
  </ItemGroup>
</Project>
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/FlightCatalog.Infrastructure.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightCatalog.Infrastructure</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Relational" Version="9.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="9.0.0">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="9.0.0" />
    <PackageReference Include="Dapper" Version="2.1.35" />
    <PackageReference Include="Npgsql" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Api/FlightCatalog.Api.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightCatalog.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Swashbuckle.AspNetCore" Version="7.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

Write-SourceFile "src/Hosts/FlightsPlatform.Api/FlightsPlatform.Api.csproj" @'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <RootNamespace>FlightsPlatform.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="Swashbuckle.AspNetCore" Version="7.0.0" />
    <PackageReference Include="Serilog.AspNetCore" Version="8.0.3" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Api\FlightCatalog.Api.csproj" />
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Infrastructure\FlightCatalog.Infrastructure.csproj" />
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/FlightCatalog.UnitTests.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <RootNamespace>FlightCatalog.UnitTests</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
    <PackageReference Include="FluentAssertions" Version="6.12.1" />
    <PackageReference Include="Moq" Version="4.20.72" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Modules\FlightCatalog\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

# ---------------------------------------------------------------------------
# SharedKernel
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== SharedKernel ==="

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.SharedKernel/Entity.cs" @'
namespace FlightsPlatform.SharedKernel;

public abstract class Entity<TId> : IEquatable<Entity<TId>>
    where TId : notnull
{
    public TId Id { get; protected set; } = default!;

    protected Entity() { }
    protected Entity(TId id) => Id = id;

    public bool Equals(Entity<TId>? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        if (GetType() != other.GetType()) return false;
        return EqualityComparer<TId>.Default.Equals(Id, other.Id);
    }

    public override bool Equals(object? obj) => Equals(obj as Entity<TId>);
    public override int GetHashCode() => HashCode.Combine(GetType(), Id);

    public static bool operator ==(Entity<TId>? a, Entity<TId>? b)
        => a is null ? b is null : a.Equals(b);

    public static bool operator !=(Entity<TId>? a, Entity<TId>? b) => !(a == b);
}
'@

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.SharedKernel/ValueObject.cs" @'
namespace FlightsPlatform.SharedKernel;

public abstract class ValueObject : IEquatable<ValueObject>
{
    protected abstract IEnumerable<object?> GetEqualityComponents();

    public bool Equals(ValueObject? other)
    {
        if (other is null || GetType() != other.GetType()) return false;
        return GetEqualityComponents().SequenceEqual(other.GetEqualityComponents());
    }

    public override bool Equals(object? obj) => Equals(obj as ValueObject);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        foreach (var component in GetEqualityComponents())
            hash.Add(component);
        return hash.ToHashCode();
    }

    public static bool operator ==(ValueObject? a, ValueObject? b)
        => a is null ? b is null : a.Equals(b);

    public static bool operator !=(ValueObject? a, ValueObject? b) => !(a == b);
}
'@

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.SharedKernel/IDomainEvent.cs" @'
namespace FlightsPlatform.SharedKernel;

public interface IDomainEvent
{
    Guid EventId { get; }
    DateTimeOffset OccurredAt { get; }
}
'@

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.SharedKernel/AggregateRoot.cs" @'
namespace FlightsPlatform.SharedKernel;

public abstract class AggregateRoot<TId> : Entity<TId>
    where TId : notnull
{
    private readonly List<IDomainEvent> _domainEvents = new List<IDomainEvent>();

    protected AggregateRoot() { }
    protected AggregateRoot(TId id) : base(id) { }

    public IReadOnlyCollection<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    protected void Raise(IDomainEvent domainEvent) => _domainEvents.Add(domainEvent);

    public void ClearDomainEvents() => _domainEvents.Clear();
}
'@

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.SharedKernel/DomainException.cs" @'
namespace FlightsPlatform.SharedKernel;

public sealed class DomainException : Exception
{
    public DomainException(string message) : base(message) { }
    public DomainException(string message, Exception inner) : base(message, inner) { }
}
'@

# ---------------------------------------------------------------------------
# FlightCatalog.Domain - Value Objects
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== FlightCatalog.Domain - Value Objects ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/ValueObjects/AirportCode.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class AirportCode : ValueObject
{
    public string Value { get; }

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

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/ValueObjects/FlightNumber.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class FlightNumber : ValueObject
{
    public string Value { get; }

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

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/ValueObjects/Route.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Route : ValueObject
{
    public AirportCode Departure { get; }
    public AirportCode Arrival { get; }

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

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/ValueObjects/Schedule.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Schedule : ValueObject
{
    public DateTimeOffset Departure { get; }
    public DateTimeOffset Arrival { get; }

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

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/ValueObjects/Money.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Money : ValueObject
{
    public decimal Amount { get; }
    public string Currency { get; }

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

# ---------------------------------------------------------------------------
# FlightCatalog.Domain - Enum, Events, Aggregates
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== FlightCatalog.Domain - Events and Aggregates ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/FlightStatus.cs" @'
namespace FlightCatalog.Domain;

public enum FlightStatus
{
    Scheduled = 0,
    Delayed = 1,
    Departed = 2,
    Arrived = 3,
    Cancelled = 4
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/Events/FlightScheduled.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record FlightScheduled(
    Guid FlightId,
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset Departure,
    DateTimeOffset Arrival) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/Events/FlightDelayed.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record FlightDelayed(
    Guid FlightId,
    string FlightNumber,
    DateTimeOffset OldDeparture,
    DateTimeOffset NewDeparture,
    bool IsSignificant) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/Events/FlightCancelled.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record FlightCancelled(
    Guid FlightId,
    string FlightNumber,
    string Reason) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Domain/Aggregates/Flight.cs" @'
using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Aggregates;

public sealed class Flight : AggregateRoot<Guid>
{
    public FlightNumber FlightNumber { get; private set; } = default!;
    public Route Route { get; private set; } = default!;
    public Schedule Schedule { get; private set; } = default!;
    public FlightStatus Status { get; private set; }
    public string AircraftModel { get; private set; } = default!;

    private Flight() { }

    private Flight(Guid id, FlightNumber number, Route route, Schedule schedule, string aircraftModel)
        : base(id)
    {
        FlightNumber = number;
        Route = route;
        Schedule = schedule;
        AircraftModel = aircraftModel;
        Status = FlightStatus.Scheduled;
    }

    public static Flight ScheduleFlight(
        FlightNumber number,
        Route route,
        Schedule schedule,
        string aircraftModel)
    {
        if (string.IsNullOrWhiteSpace(aircraftModel))
            throw new DomainException("Aircraft model is required.");

        var flight = new Flight(Guid.NewGuid(), number, route, schedule, aircraftModel);

        flight.Raise(new FlightScheduled(
            flight.Id,
            number.Value,
            route.Departure.Value,
            route.Arrival.Value,
            schedule.Departure,
            schedule.Arrival));

        return flight;
    }

    public void Delay(DateTimeOffset newDeparture, DateTimeOffset newArrival)
    {
        if (Status == FlightStatus.Cancelled)
            throw new DomainException("Cannot delay a cancelled flight.");

        if (Status == FlightStatus.Departed || Status == FlightStatus.Arrived)
            throw new DomainException("Cannot delay a flight that already departed or arrived.");

        var oldDeparture = Schedule.Departure;
        var delay = newDeparture - oldDeparture;

        Schedule = Schedule.Create(newDeparture, newArrival);
        Status = FlightStatus.Delayed;

        Raise(new FlightDelayed(
            Id,
            FlightNumber.Value,
            oldDeparture,
            newDeparture,
            delay >= TimeSpan.FromHours(3)));
    }

    public void Cancel(string reason)
    {
        if (Status == FlightStatus.Departed || Status == FlightStatus.Arrived)
            throw new DomainException("Cannot cancel a flight that already departed or arrived.");

        if (Status == FlightStatus.Cancelled)
            throw new DomainException("Flight is already cancelled.");

        if (string.IsNullOrWhiteSpace(reason))
            throw new DomainException("Cancellation reason is required.");

        Status = FlightStatus.Cancelled;
        Raise(new FlightCancelled(Id, FlightNumber.Value, reason));
    }
}
'@

# ---------------------------------------------------------------------------
# Solution + project references
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Solution ==="

$slnName = "FlightsPlatform"
if (-not (Test-Path -LiteralPath ($slnName + ".slnx"))) {
    dotnet new sln -n $slnName | Out-Null
    Write-Host ("  + " + $slnName + ".slnx")
}

$projects = @(
    "src/BuildingBlocks/FlightsPlatform.SharedKernel/FlightsPlatform.SharedKernel.csproj",
    "src/BuildingBlocks/FlightsPlatform.Application.Abstractions/FlightsPlatform.Application.Abstractions.csproj",
    "src/Modules/FlightCatalog/FlightCatalog.Domain/FlightCatalog.Domain.csproj",
    "src/Modules/FlightCatalog/FlightCatalog.Application/FlightCatalog.Application.csproj",
    "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/FlightCatalog.Infrastructure.csproj",
    "src/Modules/FlightCatalog/FlightCatalog.Api/FlightCatalog.Api.csproj",
    "src/Hosts/FlightsPlatform.Api/FlightsPlatform.Api.csproj",
    "tests/FlightCatalog.UnitTests/FlightCatalog.UnitTests.csproj"
)

foreach ($p in $projects) {
    dotnet sln ($slnName + ".slnx") add $p 2>$null | Out-Null
}

Write-Host ""
Write-Host "=== dotnet restore + build ==="
dotnet restore ($slnName + ".slnx")
dotnet build ($slnName + ".slnx") --no-restore

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "Next:"
Write-Host "  git add ."
Write-Host "  git commit -m ""Phase 1: scaffold + SharedKernel + FlightCatalog.Domain"""
Write-Host ""
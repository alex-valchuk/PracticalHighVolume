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
Write-Host "=== Phase 1 (part 2): Application + Infrastructure + Api + Tests ==="
Write-Host ("Working directory: " + (Get-Location).Path)
Write-Host ""

# ===========================================================================
# 1. BuildingBlocks.Application.Abstractions
# ===========================================================================
Write-Host "=== Application.Abstractions ==="

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.Application.Abstractions/Result.cs" @'
namespace FlightsPlatform.Application.Abstractions;

public class Result
{
    public bool IsSuccess { get; }
    public bool IsFailure => !IsSuccess;
    public string? Error { get; }
    public string? ErrorCode { get; }

    protected Result(bool isSuccess, string? error, string? errorCode)
    {
        IsSuccess = isSuccess;
        Error = error;
        ErrorCode = errorCode;
    }

    public static Result Success() => new(true, null, null);
    public static Result Failure(string error, string? errorCode = null) => new(false, error, errorCode);
}
'@

Write-SourceFile "src/BuildingBlocks/FlightsPlatform.Application.Abstractions/ResultOfT.cs" @'
namespace FlightsPlatform.Application.Abstractions;

public sealed class Result<T> : Result
{
    public T? Value { get; }

    private Result(bool isSuccess, T? value, string? error, string? errorCode)
        : base(isSuccess, error, errorCode)
    {
        Value = value;
    }

    public static Result<T> Success(T value) => new(true, value, null, null);
    public static new Result<T> Failure(string error, string? errorCode = null)
        => new(false, default, error, errorCode);
}
'@

# ===========================================================================
# 2. FlightCatalog.Application — Abstractions
# ===========================================================================
Write-Host ""
Write-Host "=== FlightCatalog.Application - Abstractions ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Abstractions/IFlightRepository.cs" @'
using FlightCatalog.Domain.Aggregates;

namespace FlightCatalog.Application.Abstractions;

public interface IFlightRepository
{
    Task<Flight?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task AddAsync(Flight flight, CancellationToken ct = default);
    void Update(Flight flight);
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Abstractions/IFlightReadRepository.cs" @'
using FlightCatalog.Application.DTOs;

namespace FlightCatalog.Application.Abstractions;

public interface IFlightReadRepository
{
    Task<FlightDto?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<IReadOnlyList<FlightDto>> SearchAsync(string from, string to, DateOnly date, CancellationToken ct = default);
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Abstractions/IUnitOfWork.cs" @'
namespace FlightCatalog.Application.Abstractions;

public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/DTOs/FlightDto.cs" @'
namespace FlightCatalog.Application.DTOs;

public sealed class FlightDto
{
    public Guid Id { get; init; }
    public string FlightNumber { get; init; } = default!;
    public string DepartureAirport { get; init; } = default!;
    public string ArrivalAirport { get; init; } = default!;
    public DateTimeOffset ScheduledDeparture { get; init; }
    public DateTimeOffset ScheduledArrival { get; init; }
    public int Status { get; init; }
    public string AircraftModel { get; init; } = default!;
}
'@

# ===========================================================================
# 3. FlightCatalog.Application — Commands
# ===========================================================================
Write-Host ""
Write-Host "=== FlightCatalog.Application - Commands ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/ScheduleFlight/ScheduleFlightCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.ScheduleFlight;

public sealed record ScheduleFlightCommand(
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset Departure,
    DateTimeOffset Arrival,
    string AircraftModel) : IRequest<Result<Guid>>;
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/ScheduleFlight/ScheduleFlightCommandValidator.cs" @'
using FluentValidation;

namespace FlightCatalog.Application.Commands.ScheduleFlight;

public sealed class ScheduleFlightCommandValidator : AbstractValidator<ScheduleFlightCommand>
{
    public ScheduleFlightCommandValidator()
    {
        RuleFor(x => x.FlightNumber).NotEmpty().MaximumLength(10);
        RuleFor(x => x.DepartureAirport).NotEmpty().Length(3);
        RuleFor(x => x.ArrivalAirport).NotEmpty().Length(3);
        RuleFor(x => x.Departure).NotEmpty();
        RuleFor(x => x.Arrival).NotEmpty().GreaterThan(x => x.Departure);
        RuleFor(x => x.AircraftModel).NotEmpty().MaximumLength(100);
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/ScheduleFlight/ScheduleFlightCommandHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Application.Commands.ScheduleFlight;

public sealed class ScheduleFlightCommandHandler : IRequestHandler<ScheduleFlightCommand, Result<Guid>>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<ScheduleFlightCommandHandler> _logger;

    public ScheduleFlightCommandHandler(
        IFlightRepository repository,
        IUnitOfWork unitOfWork,
        ILogger<ScheduleFlightCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    public async Task<Result<Guid>> Handle(ScheduleFlightCommand request, CancellationToken ct)
    {
        try
        {
            var flightNumber = FlightNumber.Create(request.FlightNumber);
            var route = Route.Create(
                AirportCode.Create(request.DepartureAirport),
                AirportCode.Create(request.ArrivalAirport));
            var schedule = Schedule.Create(request.Departure, request.Arrival);

            var flight = Flight.ScheduleFlight(flightNumber, route, schedule, request.AircraftModel);

            await _repository.AddAsync(flight, ct);
            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation("Scheduled flight {FlightId} ({FlightNumber})",
                flight.Id, flight.FlightNumber.Value);

            return Result<Guid>.Success(flight.Id);
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "Domain rule violated while scheduling flight");
            return Result<Guid>.Failure(ex.Message, "domain_error");
        }
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/DelayFlight/DelayFlightCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.DelayFlight;

public sealed record DelayFlightCommand(
    Guid FlightId,
    DateTimeOffset NewDeparture,
    DateTimeOffset NewArrival) : IRequest<Result>;
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/DelayFlight/DelayFlightCommandValidator.cs" @'
using FluentValidation;

namespace FlightCatalog.Application.Commands.DelayFlight;

public sealed class DelayFlightCommandValidator : AbstractValidator<DelayFlightCommand>
{
    public DelayFlightCommandValidator()
    {
        RuleFor(x => x.FlightId).NotEmpty();
        RuleFor(x => x.NewDeparture).NotEmpty();
        RuleFor(x => x.NewArrival).NotEmpty().GreaterThan(x => x.NewDeparture);
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/DelayFlight/DelayFlightCommandHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;

namespace FlightCatalog.Application.Commands.DelayFlight;

public sealed class DelayFlightCommandHandler : IRequestHandler<DelayFlightCommand, Result>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;

    public DelayFlightCommandHandler(IFlightRepository repository, IUnitOfWork unitOfWork)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
    }

    public async Task<Result> Handle(DelayFlightCommand request, CancellationToken ct)
    {
        var flight = await _repository.GetByIdAsync(request.FlightId, ct);
        if (flight is null)
            return Result.Failure("Flight not found", "not_found");

        try
        {
            flight.Delay(request.NewDeparture, request.NewArrival);
        }
        catch (DomainException ex)
        {
            return Result.Failure(ex.Message, "domain_error");
        }

        _repository.Update(flight);
        await _unitOfWork.SaveChangesAsync(ct);
        return Result.Success();
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/CancelFlight/CancelFlightCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed record CancelFlightCommand(Guid FlightId, string Reason) : IRequest<Result>;
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/CancelFlight/CancelFlightCommandValidator.cs" @'
using FluentValidation;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed class CancelFlightCommandValidator : AbstractValidator<CancelFlightCommand>
{
    public CancelFlightCommandValidator()
    {
        RuleFor(x => x.FlightId).NotEmpty();
        RuleFor(x => x.Reason).NotEmpty().MaximumLength(500);
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Commands/CancelFlight/CancelFlightCommandHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed class CancelFlightCommandHandler : IRequestHandler<CancelFlightCommand, Result>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;

    public CancelFlightCommandHandler(IFlightRepository repository, IUnitOfWork unitOfWork)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
    }

    public async Task<Result> Handle(CancelFlightCommand request, CancellationToken ct)
    {
        var flight = await _repository.GetByIdAsync(request.FlightId, ct);
        if (flight is null)
            return Result.Failure("Flight not found", "not_found");

        try
        {
            flight.Cancel(request.Reason);
        }
        catch (DomainException ex)
        {
            return Result.Failure(ex.Message, "domain_error");
        }

        _repository.Update(flight);
        await _unitOfWork.SaveChangesAsync(ct);
        return Result.Success();
    }
}
'@

# ===========================================================================
# 4. FlightCatalog.Application — Queries
# ===========================================================================
Write-Host ""
Write-Host "=== FlightCatalog.Application - Queries ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Queries/GetFlightById/GetFlightByIdQuery.cs" @'
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetFlightById;

public sealed record GetFlightByIdQuery(Guid FlightId) : IRequest<FlightDto?>;
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Queries/GetFlightById/GetFlightByIdQueryHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetFlightById;

public sealed class GetFlightByIdQueryHandler : IRequestHandler<GetFlightByIdQuery, FlightDto?>
{
    private readonly IFlightReadRepository _readRepository;

    public GetFlightByIdQueryHandler(IFlightReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<FlightDto?> Handle(GetFlightByIdQuery request, CancellationToken ct)
        => _readRepository.GetByIdAsync(request.FlightId, ct);
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Queries/SearchFlights/SearchFlightsQuery.cs" @'
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.SearchFlights;

public sealed record SearchFlightsQuery(
    string From,
    string To,
    DateOnly Date) : IRequest<IReadOnlyList<FlightDto>>;
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Queries/SearchFlights/SearchFlightsQueryValidator.cs" @'
using FluentValidation;

namespace FlightCatalog.Application.Queries.SearchFlights;

public sealed class SearchFlightsQueryValidator : AbstractValidator<SearchFlightsQuery>
{
    public SearchFlightsQueryValidator()
    {
        RuleFor(x => x.From).NotEmpty().Length(3);
        RuleFor(x => x.To).NotEmpty().Length(3);
        RuleFor(x => x.Date).NotEmpty();
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Queries/SearchFlights/SearchFlightsQueryHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.SearchFlights;

public sealed class SearchFlightsQueryHandler : IRequestHandler<SearchFlightsQuery, IReadOnlyList<FlightDto>>
{
    private readonly IFlightReadRepository _readRepository;

    public SearchFlightsQueryHandler(IFlightReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<IReadOnlyList<FlightDto>> Handle(SearchFlightsQuery request, CancellationToken ct)
        => _readRepository.SearchAsync(request.From, request.To, request.Date, ct);
}
'@

# ===========================================================================
# 5. FlightCatalog.Application — Behaviors + DI
# ===========================================================================
Write-Host ""
Write-Host "=== FlightCatalog.Application - Behaviors + DI ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Behaviors/LoggingBehavior.cs" @'
using System.Diagnostics;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Application.Behaviors;

public sealed class LoggingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<LoggingBehavior<TRequest, TResponse>> _logger;

    public LoggingBehavior(ILogger<LoggingBehavior<TRequest, TResponse>> logger)
        => _logger = logger;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var name = typeof(TRequest).Name;
        _logger.LogInformation("Handling {RequestName}", name);

        var sw = Stopwatch.StartNew();
        try
        {
            var response = await next();
            sw.Stop();
            _logger.LogInformation("Handled {RequestName} in {Elapsed} ms", name, sw.ElapsedMilliseconds);
            return response;
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex, "Error handling {RequestName} after {Elapsed} ms",
                name, sw.ElapsedMilliseconds);
            throw;
        }
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/Behaviors/ValidationBehavior.cs" @'
using FluentValidation;
using MediatR;

namespace FlightCatalog.Application.Behaviors;

public sealed class ValidationBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehavior(IEnumerable<IValidator<TRequest>> validators)
        => _validators = validators;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (!_validators.Any())
            return await next();

        var context = new ValidationContext<TRequest>(request);
        var results = await Task.WhenAll(_validators.Select(v => v.ValidateAsync(context, ct)));
        var failures = results.SelectMany(r => r.Errors).Where(f => f is not null).ToList();

        if (failures.Count != 0)
            throw new ValidationException(failures);

        return await next();
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Application/DependencyInjection.cs" @'
using System.Reflection;
using FlightCatalog.Application.Behaviors;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace FlightCatalog.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddFlightCatalogApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();

        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(assembly);
            cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        });

        services.AddValidatorsFromAssembly(assembly, includeInternalTypes: true);

        return services;
    }
}
'@

# ===========================================================================
# 6. FlightCatalog.Infrastructure
# ===========================================================================
Write-Host ""
Write-Host "=== FlightCatalog.Infrastructure ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Persistence/FlightCatalogDbContext.cs" @'
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence;

public sealed class FlightCatalogDbContext : DbContext
{
    public const string SchemaName = "flight_catalog";

    public FlightCatalogDbContext(DbContextOptions<FlightCatalogDbContext> options)
        : base(options) { }

    public DbSet<Flight> Flights => Set<Flight>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(SchemaName);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FlightCatalogDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Persistence/Configurations/FlightConfiguration.cs" @'
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FlightCatalog.Infrastructure.Persistence.Configurations;

public sealed class FlightConfiguration : IEntityTypeConfiguration<Flight>
{
    public void Configure(EntityTypeBuilder<Flight> builder)
    {
        builder.ToTable("flights");
        builder.HasKey(f => f.Id);
        builder.Property(f => f.Id).HasColumnName("id");

        builder.Property(f => f.Status)
            .HasColumnName("status")
            .HasConversion<int>()
            .IsRequired();

        builder.Property(f => f.AircraftModel)
            .HasColumnName("aircraft_model")
            .HasMaxLength(100)
            .IsRequired();

        builder.ComplexProperty(f => f.FlightNumber, b =>
        {
            b.Property(x => x.Value).HasColumnName("flight_no").HasMaxLength(10).IsRequired();
        });

        builder.ComplexProperty(f => f.Route, route =>
        {
            route.ComplexProperty(r => r.Departure, dep =>
            {
                dep.Property(x => x.Value).HasColumnName("departure_airport").HasMaxLength(3).IsRequired();
            });
            route.ComplexProperty(r => r.Arrival, arr =>
            {
                arr.Property(x => x.Value).HasColumnName("arrival_airport").HasMaxLength(3).IsRequired();
            });
        });

        builder.ComplexProperty(f => f.Schedule, sched =>
        {
            sched.Property(x => x.Departure).HasColumnName("scheduled_departure").IsRequired();
            sched.Property(x => x.Arrival).HasColumnName("scheduled_arrival").IsRequired();
        });

        builder.HasIndex(f => new { f.Status });
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Persistence/Repositories/FlightRepository.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

public sealed class FlightRepository : IFlightRepository
{
    private readonly FlightCatalogDbContext _db;

    public FlightRepository(FlightCatalogDbContext db) => _db = db;

    public Task<Flight?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => _db.Flights.FirstOrDefaultAsync(f => f.Id == id, ct);

    public async Task AddAsync(Flight flight, CancellationToken ct = default)
        => await _db.Flights.AddAsync(flight, ct);

    public void Update(Flight flight) => _db.Flights.Update(flight);
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Persistence/Repositories/FlightReadRepository.cs" @'
using Dapper;
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using Npgsql;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

public sealed class FlightReadRepository : IFlightReadRepository
{
    private readonly NpgsqlDataSource _dataSource;

    public FlightReadRepository(NpgsqlDataSource dataSource) => _dataSource = dataSource;

    public async Task<FlightDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        const string sql = @"
            SELECT id                    AS Id,
                   flight_no             AS FlightNumber,
                   departure_airport     AS DepartureAirport,
                   arrival_airport       AS ArrivalAirport,
                   scheduled_departure   AS ScheduledDeparture,
                   scheduled_arrival     AS ScheduledArrival,
                   status                AS Status,
                   aircraft_model        AS AircraftModel
            FROM flight_catalog.flights
            WHERE id = @Id";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        return await conn.QueryFirstOrDefaultAsync<FlightDto>(
            new CommandDefinition(sql, new { Id = id }, cancellationToken: ct));
    }

    public async Task<IReadOnlyList<FlightDto>> SearchAsync(
        string from, string to, DateOnly date, CancellationToken ct = default)
    {
        const string sql = @"
            SELECT id                    AS Id,
                   flight_no             AS FlightNumber,
                   departure_airport     AS DepartureAirport,
                   arrival_airport       AS ArrivalAirport,
                   scheduled_departure   AS ScheduledDeparture,
                   scheduled_arrival     AS ScheduledArrival,
                   status                AS Status,
                   aircraft_model        AS AircraftModel
            FROM flight_catalog.flights
            WHERE departure_airport = @From
              AND arrival_airport   = @To
              AND scheduled_departure >= @StartOfDay
              AND scheduled_departure <  @EndOfDay
            ORDER BY scheduled_departure";

        var start = date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        var end = start.AddDays(1);

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        var rows = await conn.QueryAsync<FlightDto>(
            new CommandDefinition(sql,
                new { From = from.ToUpperInvariant(), To = to.ToUpperInvariant(), StartOfDay = start, EndOfDay = end },
                cancellationToken: ct));

        return rows.ToList();
    }
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Persistence/UnitOfWork.cs" @'
using FlightCatalog.Application.Abstractions;

namespace FlightCatalog.Infrastructure.Persistence;

public sealed class UnitOfWork : IUnitOfWork
{
    private readonly FlightCatalogDbContext _db;

    public UnitOfWork(FlightCatalogDbContext db) => _db = db;

    public Task<int> SaveChangesAsync(CancellationToken ct = default) => _db.SaveChangesAsync(ct);
}
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/DependencyInjection.cs" @'
using FlightCatalog.Application.Abstractions;
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
        var connectionString = configuration.GetConnectionString("FlightCatalog")
            ?? throw new InvalidOperationException(
                "Connection string 'FlightCatalog' is not configured.");

        services.AddSingleton(NpgsqlDataSource.Create(connectionString));

        services.AddDbContext<FlightCatalogDbContext>(opts =>
            opts.UseNpgsql(connectionString));

        services.AddScoped<IFlightRepository, FlightRepository>();
        services.AddScoped<IFlightReadRepository, FlightReadRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        return services;
    }
}
'@

# ===========================================================================
# 7. FlightCatalog.Api
# ===========================================================================
Write-Host ""
Write-Host "=== FlightCatalog.Api ==="

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Api/Contracts/ScheduleFlightRequest.cs" @'
namespace FlightCatalog.Api.Contracts;

public sealed record ScheduleFlightRequest(
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset Departure,
    DateTimeOffset Arrival,
    string AircraftModel);
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Api/Contracts/DelayFlightRequest.cs" @'
namespace FlightCatalog.Api.Contracts;

public sealed record DelayFlightRequest(
    DateTimeOffset NewDeparture,
    DateTimeOffset NewArrival);
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Api/Contracts/CancelFlightRequest.cs" @'
namespace FlightCatalog.Api.Contracts;

public sealed record CancelFlightRequest(string Reason);
'@

Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Api/FlightEndpoints.cs" @'
using FlightCatalog.Api.Contracts;
using FlightCatalog.Application.Commands.CancelFlight;
using FlightCatalog.Application.Commands.DelayFlight;
using FlightCatalog.Application.Commands.ScheduleFlight;
using FlightCatalog.Application.Queries.GetFlightById;
using FlightCatalog.Application.Queries.SearchFlights;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace FlightCatalog.Api;

public static class FlightEndpoints
{
    public static IEndpointRouteBuilder MapFlightCatalogEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/flight-catalog/flights").WithTags("Flight Catalog");

        group.MapPost("/", async (
            ScheduleFlightRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new ScheduleFlightCommand(
                req.FlightNumber, req.DepartureAirport, req.ArrivalAirport,
                req.Departure, req.Arrival, req.AircraftModel);

            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/flight-catalog/flights/{result.Value}",
                    new { id = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/delay", async (
            Guid id,
            DelayFlightRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new DelayFlightCommand(id, req.NewDeparture, req.NewArrival), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/cancel", async (
            Guid id,
            CancelFlightRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new CancelFlightCommand(id, req.Reason), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapGet("/{id:guid}", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetFlightByIdQuery(id), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapGet("/", async (
            string from,
            string to,
            DateOnly date,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var rows = await mediator.Send(new SearchFlightsQuery(from, to, date), ct);
            return Results.Ok(rows);
        });

        return app;
    }
}
'@

# --- Update csproj for FlightCatalog.Api (needs FrameworkReference) ---
Write-SourceFile "src/Modules/FlightCatalog/FlightCatalog.Api/FlightCatalog.Api.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightCatalog.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

# --- Update csproj for FlightCatalog.Application (add DI abstractions) ---
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
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Domain\FlightCatalog.Domain.csproj" />
    <ProjectReference Include="..\..\..\BuildingBlocks\FlightsPlatform.Application.Abstractions\FlightsPlatform.Application.Abstractions.csproj" />
  </ItemGroup>
</Project>
'@

# --- Update csproj for FlightCatalog.Infrastructure (add Npgsql.DataSource + config abstractions) ---
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
    <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

# ===========================================================================
# 8. Host — Program.cs, appsettings, csproj
# ===========================================================================
Write-Host ""
Write-Host "=== Host updates ==="

Write-SourceFile "src/Hosts/FlightsPlatform.Api/Program.cs" @'
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
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
            (object)new { error = "validation_failed",
                          details = ve.Errors.Select(e => e.ErrorMessage) }),
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

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await db.Database.EnsureCreatedAsync();
}

app.Run();
'@

Write-SourceFile "src/Hosts/FlightsPlatform.Api/appsettings.json" @'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "ConnectionStrings": {
    "FlightCatalog": "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"
  },
  "AllowedHosts": "*"
}
'@

Write-SourceFile "src/Hosts/FlightsPlatform.Api/appsettings.Development.json" @'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore.Database.Command": "Warning"
    }
  }
}
'@

Write-SourceFile "src/Hosts/FlightsPlatform.Api/FlightsPlatform.Api.csproj" @'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <RootNamespace>FlightsPlatform.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="Scalar.AspNetCore" Version="2.0.17" />
    <PackageReference Include="Serilog.AspNetCore" Version="8.0.3" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Api\FlightCatalog.Api.csproj" />
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Infrastructure\FlightCatalog.Infrastructure.csproj" />
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

# ===========================================================================
# 9. Tests
# ===========================================================================
Write-Host ""
Write-Host "=== Tests ==="

Write-SourceFile "tests/FlightCatalog.UnitTests/Domain/AirportCodeTests.cs" @'
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class AirportCodeTests
{
    [Theory]
    [InlineData("SVO")]
    [InlineData("svo")]
    [InlineData(" OVB ")]
    public void Create_WithValidInput_NormalizesAndSucceeds(string input)
    {
        var code = AirportCode.Create(input);
        code.Value.Should().Be(input.Trim().ToUpperInvariant());
    }

    [Theory]
    [InlineData("")]
    [InlineData("AB")]
    [InlineData("ABCD")]
    [InlineData("S1O")]
    public void Create_WithInvalidInput_Throws(string input)
    {
        var act = () => AirportCode.Create(input);
        act.Should().Throw<DomainException>();
    }
}
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/Domain/FlightNumberTests.cs" @'
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class FlightNumberTests
{
    [Theory]
    [InlineData("PG-0421")]
    [InlineData("pg-421")]
    [InlineData("AA-1234")]
    public void Create_WithValidInput_Succeeds(string input)
    {
        var number = FlightNumber.Create(input);
        number.Value.Should().StartWith(input[..2].ToUpperInvariant());
    }

    [Theory]
    [InlineData("")]
    [InlineData("PG0421")]
    [InlineData("P-0421")]
    [InlineData("PG-ABCD")]
    [InlineData("PG-12345")]
    public void Create_WithInvalidInput_Throws(string input)
    {
        var act = () => FlightNumber.Create(input);
        act.Should().Throw<DomainException>();
    }
}
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/Domain/RouteTests.cs" @'
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class RouteTests
{
    [Fact]
    public void Create_WithDifferentAirports_Succeeds()
    {
        var route = Route.Create(AirportCode.Create("SVO"), AirportCode.Create("OVB"));
        route.Departure.Value.Should().Be("SVO");
        route.Arrival.Value.Should().Be("OVB");
    }

    [Fact]
    public void Create_WithSameAirport_Throws()
    {
        var act = () => Route.Create(AirportCode.Create("SVO"), AirportCode.Create("SVO"));
        act.Should().Throw<DomainException>();
    }
}
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/Domain/ScheduleTests.cs" @'
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class ScheduleTests
{
    [Fact]
    public void Create_WithValidTimes_Succeeds()
    {
        var now = DateTimeOffset.UtcNow;
        var schedule = Schedule.Create(now, now.AddHours(3));
        schedule.Arrival.Should().BeAfter(schedule.Departure);
    }

    [Fact]
    public void Create_WithArrivalBeforeDeparture_Throws()
    {
        var now = DateTimeOffset.UtcNow;
        var act = () => Schedule.Create(now, now.AddHours(-1));
        act.Should().Throw<DomainException>();
    }
}
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/Domain/FlightAggregateTests.cs" @'
using FlightCatalog.Domain;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class FlightAggregateTests
{
    private static Flight CreateFlight()
    {
        var now = DateTimeOffset.UtcNow;
        return Flight.ScheduleFlight(
            FlightNumber.Create("PG-0001"),
            Route.Create(AirportCode.Create("SVO"), AirportCode.Create("OVB")),
            Schedule.Create(now.AddDays(1), now.AddDays(1).AddHours(4)),
            "Airbus A320");
    }

    [Fact]
    public void ScheduleFlight_RaisesFlightScheduledEvent()
    {
        var flight = CreateFlight();
        flight.DomainEvents.Should().ContainSingle(e => e is FlightScheduled);
        flight.Status.Should().Be(FlightStatus.Scheduled);
    }

    [Fact]
    public void Delay_WithinReasonableWindow_RaisesFlightDelayed()
    {
        var flight = CreateFlight();
        flight.ClearDomainEvents();

        var newDep = flight.Schedule.Departure.AddHours(1);
        flight.Delay(newDep, flight.Schedule.Arrival.AddHours(1));

        flight.Status.Should().Be(FlightStatus.Delayed);
        var evt = flight.DomainEvents.OfType<FlightDelayed>().Single();
        evt.IsSignificant.Should().BeFalse();
    }

    [Fact]
    public void Delay_MoreThanThreeHours_MarksSignificant()
    {
        var flight = CreateFlight();
        flight.ClearDomainEvents();

        var newDep = flight.Schedule.Departure.AddHours(5);
        flight.Delay(newDep, flight.Schedule.Arrival.AddHours(5));

        var evt = flight.DomainEvents.OfType<FlightDelayed>().Single();
        evt.IsSignificant.Should().BeTrue();
    }

    [Fact]
    public void Cancel_OnScheduledFlight_SucceedsAndRaisesEvent()
    {
        var flight = CreateFlight();
        flight.ClearDomainEvents();

        flight.Cancel("weather");

        flight.Status.Should().Be(FlightStatus.Cancelled);
        flight.DomainEvents.Should().ContainSingle(e => e is FlightCancelled);
    }

    [Fact]
    public void Cancel_OnAlreadyCancelled_Throws()
    {
        var flight = CreateFlight();
        flight.Cancel("weather");

        var act = () => flight.Cancel("duplicate");
        act.Should().Throw<DomainException>();
    }
}
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/Application/ScheduleFlightCommandHandlerTests.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.Commands.ScheduleFlight;
using FlightCatalog.Domain.Aggregates;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class ScheduleFlightCommandHandlerTests
{
    private static ScheduleFlightCommandHandler BuildHandler(
        Mock<IFlightRepository> repo,
        Mock<IUnitOfWork> uow)
        => new(repo.Object, uow.Object, NullLogger<ScheduleFlightCommandHandler>.Instance);

    [Fact]
    public async Task Handle_WithValidRequest_ReturnsSuccess()
    {
        var repo = new Mock<IFlightRepository>();
        repo.Setup(r => r.AddAsync(It.IsAny<Flight>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(1);

        var handler = BuildHandler(repo, uow);

        var cmd = new ScheduleFlightCommand(
            "PG-0421", "SVO", "OVB",
            DateTimeOffset.UtcNow.AddDays(1),
            DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
            "Airbus A320");

        var result = await handler.Handle(cmd, CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();
        repo.Verify(r => r.AddAsync(It.IsAny<Flight>(), It.IsAny<CancellationToken>()), Times.Once);
        uow.Verify(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_WithSameDepartureAndArrival_ReturnsFailure()
    {
        var repo = new Mock<IFlightRepository>();
        var uow = new Mock<IUnitOfWork>();
        var handler = BuildHandler(repo, uow);

        var cmd = new ScheduleFlightCommand(
            "PG-0421", "SVO", "SVO",
            DateTimeOffset.UtcNow.AddDays(1),
            DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
            "Airbus A320");

        var result = await handler.Handle(cmd, CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("domain_error");
    }
}
'@

Write-SourceFile "tests/FlightCatalog.UnitTests/Application/CancelFlightCommandHandlerTests.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.Commands.CancelFlight;
using FlightCatalog.Domain;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FluentAssertions;
using Moq;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class CancelFlightCommandHandlerTests
{
    [Fact]
    public async Task Handle_WhenFlightNotFound_ReturnsFailure()
    {
        var repo = new Mock<IFlightRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Flight?)null);

        var uow = new Mock<IUnitOfWork>();
        var handler = new CancelFlightCommandHandler(repo.Object, uow.Object);

        var result = await handler.Handle(new CancelFlightCommand(Guid.NewGuid(), "test"),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_WhenFlightExists_Succeeds()
    {
        var now = DateTimeOffset.UtcNow;
        var flight = Flight.ScheduleFlight(
            FlightNumber.Create("PG-0001"),
            Route.Create(AirportCode.Create("SVO"), AirportCode.Create("OVB")),
            Schedule.Create(now.AddDays(1), now.AddDays(1).AddHours(4)),
            "Airbus A320");

        var repo = new Mock<IFlightRepository>();
        repo.Setup(r => r.GetByIdAsync(flight.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(flight);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new CancelFlightCommandHandler(repo.Object, uow.Object);
        var result = await handler.Handle(new CancelFlightCommand(flight.Id, "weather"),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        flight.Status.Should().Be(FlightStatus.Cancelled);
    }
}
'@

# ===========================================================================
# 10. Docs
# ===========================================================================
Write-Host ""
Write-Host "=== Docs ==="

Write-SourceFile "docs/adr/ADR-001-modular-monolith.md" @'
# ADR-001: Modular Monolith Instead of Microservices

## Status
Accepted

## Context
We are building a flight booking platform on top of a large existing Postgres
database (demo bookings database, ~1.3 GB). Team size is small; delivery speed
matters more than unlimited horizontal scaling at this stage.

## Decision
We start with a modular monolith. Each bounded context (Flight Catalog,
Booking, Pricing) is a separate module inside one solution, one process,
one deployment. Modules communicate via in-process MediatR notifications
(and via an outbox to RabbitMQ later).

## Consequences
Positive:
- Fast local development, single debugging session.
- No distributed transactions, no saga needed yet.
- Strong module boundaries (Domain / Application / Infrastructure / Api),
  so slicing into services later is a mechanical step.

Negative:
- Single process, single point of failure until scaled.
- Requires discipline: no direct calls between modules.

## When to revisit
When a module needs independent scaling, different tech stack, or its own
deployment cadence, we extract it as a service using the same boundaries.
'@

Write-SourceFile "docs/adr/ADR-002-cqrs-split.md" @'
# ADR-002: CQRS with Split Read/Write Repositories

## Status
Accepted

## Context
Flight Catalog workloads are asymmetric: reads dominate (search, lookup),
writes are rare (schedule, delay, cancel). EF Core is great for writes
(change tracking, invariants) but slow for complex read queries.

## Decision
We split repositories at the contract level:
- IFlightRepository (write) - used by command handlers, backed by EF Core.
- IFlightReadRepository (read) - used by query handlers, backed by Dapper.

Both currently point to the same Postgres database and the same table
flight_catalog.flights.

## Consequences
Positive:
- Read side is fast and predictable (raw SQL, DTOs, no change tracking).
- Write side keeps rich domain model and invariants.
- Later we can point the read side at a read-replica or Redis cache
  without touching the domain.

Negative:
- Two persistence technologies in one module.
- Risk of schema drift between EF Core model and raw SQL - mitigated by
  integration tests.

## When to revisit
When read load grows, we move the read side to a read-replica. If read
throughput becomes bottleneck, we add Redis caching on top of the read
repository.
'@

Write-SourceFile "docs/adr/ADR-003-own-schema.md" @'
# ADR-003: Own Schema for Flight Catalog

## Status
Accepted

## Context
The Postgres instance already contains the demo bookings database with a
bookings schema (airports, flights, tickets, etc.). We need to decide whether
to map our domain onto that schema or create our own.

## Decision
We create our own schema: flight_catalog. Our aggregates live there.
The bookings schema is treated as an external data source, integrated via
an anti-corruption layer in a later phase.

## Consequences
Positive:
- Domain is not polluted by foreign naming, types, or invariants.
- We own our schema: can evolve it independently.
- Clear separation of "our data" vs "external data".

Negative:
- Some duplication: airports, aircraft models may exist in both schemas.
- Need a sync mechanism (later phase) to keep reference data fresh.

## When to revisit
If we ever migrate onto an existing corporate schema, this decision is
revisited. For the current scope, isolation wins.
'@

Write-SourceFile "README.md" @'
# Flights Platform

A modular monolith demonstrating Clean Architecture, CQRS, DDD,
and distributed-systems patterns on top of a real Postgres demo database.

## Architecture

### Bounded contexts
- **Flight Catalog** (implemented) - schedule, flights, aircraft, airports.
- **Booking** (planned) - reservations, tickets, passengers, cancellations.
- **Pricing** (planned) - fares, discounts, dynamic pricing.
- **Notification** (planned) - email, SMS, push, event-driven.

Modules communicate in-process via MediatR and (later) via RabbitMQ events.

### Layering
Each module has the same shape:

    Module/
      Module.Domain            (no external deps)
      Module.Application       (MediatR commands/queries, FluentValidation,
                                Dapper-based read abstractions)
      Module.Infrastructure    (EF Core + Dapper, repositories)
      Module.Api               (Minimal API endpoints exposed to the host)

The host (FlightsPlatform.Api) only wires modules together. It has no
business logic.

## Tech stack
- .NET 10, ASP.NET Core
- MediatR 12, FluentValidation 11
- EF Core 9 (write side) + Dapper 2.1 (read side)
- PostgreSQL 16 (demo bookings database)
- Scalar for OpenAPI UI

## Running locally

1. Start Postgres:

       docker compose up -d

2. Restore packages:

       dotnet restore

3. Run the API:

       dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https

4. Open Scalar UI:

       https://localhost:50943/scalar/v1

## Tests

    dotnet test

## Architecture Decision Records
See docs/adr/.
'@

# ===========================================================================
# 11. Add new project to solution + build
# ===========================================================================
Write-Host ""
Write-Host "=== Solution and build ==="

$sln = Get-ChildItem -Filter "*.slnx" -File | Select-Object -First 1
if (-not $sln) { $sln = Get-ChildItem -Filter "*.sln" -File | Select-Object -First 1 }

if ($sln) {
    Write-Host ("  solution: " + $sln.Name)
} else {
    Write-Host "  no .sln/.slnx found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== dotnet restore + build ==="
dotnet restore
dotnet build --no-restore

Write-Host ""
Write-Host "=== dotnet test ==="
dotnet test --no-build --nologo

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "Next:"
Write-Host "  git add ."
Write-Host "  git commit -m ""Phase 1: CQRS + Clean Architecture + tests"""
Write-Host ""
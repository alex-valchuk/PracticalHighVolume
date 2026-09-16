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
Write-Host "=== Phase 2: Integration with external source (bookings) ==="
Write-Host ("Working directory: " + (Get-Location).Path)
Write-Host ""

$domain   = "src/Modules/FlightCatalog/FlightCatalog.Domain"
$app      = "src/Modules/FlightCatalog/FlightCatalog.Application"
$infra    = "src/Modules/FlightCatalog/FlightCatalog.Infrastructure"
$api      = "src/Modules/FlightCatalog/FlightCatalog.Api"
$hostDir  = "src/Hosts/FlightsPlatform.Api"
$tests    = "tests/FlightCatalog.UnitTests"
$docs     = "docs/adr"

# ===========================================================================
# 1. Domain: Coordinates VO
# ===========================================================================
Write-Host ""
Write-Host "=== Domain: Coordinates ==="

Write-SourceFile "$domain/ValueObjects/Coordinates.cs" @'
using System.Globalization;
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Coordinates : ValueObject
{
    public double Latitude { get; private set; }
    public double Longitude { get; private set; }

    private Coordinates() { }

    private Coordinates(double latitude, double longitude)
    {
        Latitude = latitude;
        Longitude = longitude;
    }

    public static Coordinates Create(double latitude, double longitude)
    {
        if (latitude < -90 || latitude > 90)
            throw new DomainException("Latitude must be in range [-90, 90].");
        if (longitude < -180 || longitude > 180)
            throw new DomainException("Longitude must be in range [-180, 180].");

        return new Coordinates(latitude, longitude);
    }

    // Parses Postgres point literal "(lon,lat)" -> Coordinates(lat, lon)
    public static Coordinates Parse(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            throw new DomainException("Coordinates string is empty.");

        var trimmed = raw.Trim();
        if (trimmed.StartsWith("(") && trimmed.EndsWith(")"))
            trimmed = trimmed[1..^1];

        var parts = trimmed.Split(',');
        if (parts.Length != 2)
            throw new DomainException("Invalid coordinates format: " + raw);

        if (!double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var lon))
            throw new DomainException("Invalid longitude in: " + raw);
        if (!double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var lat))
            throw new DomainException("Invalid latitude in: " + raw);

        return Create(lat, lon);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Latitude;
        yield return Longitude;
    }

    public override string ToString()
        => string.Format(CultureInfo.InvariantCulture, "({0},{1})", Longitude, Latitude);
}
'@

# ===========================================================================
# 2. Domain: Airport aggregate + event
# ===========================================================================
Write-Host ""
Write-Host "=== Domain: Airport ==="

Write-SourceFile "$domain/Events/AirportSynced.cs" @'
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record AirportSynced(
    Guid AirportId,
    string Code,
    string Name,
    string City) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-SourceFile "$domain/Aggregates/Airport.cs" @'
using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Aggregates;

public sealed class Airport : AggregateRoot<Guid>
{
    public AirportCode Code { get; private set; } = default!;
    public string Name { get; private set; } = default!;
    public string City { get; private set; } = default!;
    public string Timezone { get; private set; } = default!;
    public Coordinates Coordinates { get; private set; } = default!;

    private Airport() { }

    private Airport(Guid id, AirportCode code, string name, string city, string timezone, Coordinates coordinates)
        : base(id)
    {
        Code = code;
        Name = name;
        City = city;
        Timezone = timezone;
        Coordinates = coordinates;
    }

    public static Airport Create(
        AirportCode code,
        string name,
        string city,
        string timezone,
        Coordinates coordinates)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Airport name is required.");
        if (string.IsNullOrWhiteSpace(city))
            throw new DomainException("City is required.");
        if (string.IsNullOrWhiteSpace(timezone))
            throw new DomainException("Timezone is required.");

        var airport = new Airport(Guid.NewGuid(), code, name.Trim(), city.Trim(), timezone.Trim(), coordinates);

        airport.Raise(new AirportSynced(airport.Id, code.Value, name, city));

        return airport;
    }

    public void UpdateInfo(string name, string city, string timezone, Coordinates coordinates)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Airport name is required.");
        if (string.IsNullOrWhiteSpace(city))
            throw new DomainException("City is required.");
        if (string.IsNullOrWhiteSpace(timezone))
            throw new DomainException("Timezone is required.");

        Name = name.Trim();
        City = city.Trim();
        Timezone = timezone.Trim();
        Coordinates = coordinates;
    }
}
'@

# ===========================================================================
# 3. Application: Abstractions
# ===========================================================================
Write-Host ""
Write-Host "=== Application: Abstractions ==="

Write-SourceFile "$app/Abstractions/IAirportRepository.cs" @'
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;

namespace FlightCatalog.Application.Abstractions;

public interface IAirportRepository
{
    Task<Airport?> GetByCodeAsync(AirportCode code, CancellationToken ct = default);
    Task<IReadOnlyList<Airport>> GetAllAsync(CancellationToken ct = default);
    Task AddAsync(Airport airport, CancellationToken ct = default);
    void Update(Airport airport);
}
'@

Write-SourceFile "$app/Abstractions/IAirportReadRepository.cs" @'
using FlightCatalog.Application.DTOs;

namespace FlightCatalog.Application.Abstractions;

public interface IAirportReadRepository
{
    Task<AirportDto?> GetByCodeAsync(string code, CancellationToken ct = default);
    Task<(IReadOnlyList<AirportDto> Items, int Total)> GetAllAsync(int page, int pageSize, CancellationToken ct = default);
}
'@

Write-SourceFile "$app/Abstractions/IBookingsSourceReader.cs" @'
namespace FlightCatalog.Application.Abstractions;

public sealed record ExternalAirport(
    string Code,
    string Name,
    string City,
    string Timezone,
    string Coordinates);

public interface IBookingsSourceReader
{
    Task<IReadOnlyList<ExternalAirport>> ReadAirportsAsync(CancellationToken ct = default);
}
'@

# ===========================================================================
# 4. Application: DTOs
# ===========================================================================
Write-Host ""
Write-Host "=== Application: DTOs ==="

Write-SourceFile "$app/DTOs/AirportDto.cs" @'
namespace FlightCatalog.Application.DTOs;

public sealed class AirportDto
{
    public Guid Id { get; init; }
    public string Code { get; init; } = default!;
    public string Name { get; init; } = default!;
    public string City { get; init; } = default!;
    public string Timezone { get; init; } = default!;
    public double Latitude { get; init; }
    public double Longitude { get; init; }
}
'@

Write-SourceFile "$app/DTOs/FlightDto.cs" @'
namespace FlightCatalog.Application.DTOs;

public sealed class FlightDto
{
    public Guid Id { get; init; }
    public string FlightNumber { get; init; } = default!;
    public string DepartureAirport { get; init; } = default!;
    public string? DepartureAirportName { get; init; }
    public string ArrivalAirport { get; init; } = default!;
    public string? ArrivalAirportName { get; init; }
    public DateTimeOffset ScheduledDeparture { get; init; }
    public DateTimeOffset ScheduledArrival { get; init; }
    public int Status { get; init; }
    public string AircraftModel { get; init; } = default!;
}
'@

# ===========================================================================
# 5. Application: SyncAirports command
# ===========================================================================
Write-Host ""
Write-Host "=== Application: SyncAirports command ==="

Write-SourceFile "$app/Commands/SyncAirports/SyncAirportsCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.SyncAirports;

public sealed record SyncAirportsResult(int Read, int Created, int Updated, int Skipped);

public sealed record SyncAirportsCommand : IRequest<Result<SyncAirportsResult>>;
'@

Write-SourceFile "$app/Commands/SyncAirports/SyncAirportsCommandHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Application.Commands.SyncAirports;

public sealed class SyncAirportsCommandHandler : IRequestHandler<SyncAirportsCommand, Result<SyncAirportsResult>>
{
    private readonly IBookingsSourceReader _source;
    private readonly IAirportRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<SyncAirportsCommandHandler> _logger;

    public SyncAirportsCommandHandler(
        IBookingsSourceReader source,
        IAirportRepository repository,
        IUnitOfWork unitOfWork,
        ILogger<SyncAirportsCommandHandler> logger)
    {
        _source = source;
        _repository = repository;
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    public async Task<Result<SyncAirportsResult>> Handle(SyncAirportsCommand request, CancellationToken ct)
    {
        var external = await _source.ReadAirportsAsync(ct);
        _logger.LogInformation("Read {Count} airports from external source", external.Count);

        int created = 0, updated = 0, skipped = 0;

        foreach (var row in external)
        {
            try
            {
                var code = AirportCode.Create(row.Code);
                var coords = Coordinates.Parse(row.Coordinates);

                var existing = await _repository.GetByCodeAsync(code, ct);
                if (existing is null)
                {
                    var airport = Airport.Create(code, row.Name, row.City, row.Timezone, coords);
                    await _repository.AddAsync(airport, ct);
                    created++;
                }
                else
                {
                    existing.UpdateInfo(row.Name, row.City, row.Timezone, coords);
                    _repository.Update(existing);
                    updated++;
                }
            }
            catch (DomainException ex)
            {
                _logger.LogWarning("Skipping airport {Code}: {Reason}", row.Code, ex.Message);
                skipped++;
            }
        }

        await _unitOfWork.SaveChangesAsync(ct);

        var result = new SyncAirportsResult(external.Count, created, updated, skipped);
        _logger.LogInformation(
            "Airport sync complete: read={Read}, created={Created}, updated={Updated}, skipped={Skipped}",
            result.Read, result.Created, result.Updated, result.Skipped);

        return Result<SyncAirportsResult>.Success(result);
    }
}
'@

# ===========================================================================
# 6. Application: Airport queries
# ===========================================================================
Write-Host ""
Write-Host "=== Application: Airport queries ==="

Write-SourceFile "$app/Queries/GetAirportByCode/GetAirportByCodeQuery.cs" @'
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAirportByCode;

public sealed record GetAirportByCodeQuery(string Code) : IRequest<AirportDto?>;
'@

Write-SourceFile "$app/Queries/GetAirportByCode/GetAirportByCodeQueryHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAirportByCode;

public sealed class GetAirportByCodeQueryHandler : IRequestHandler<GetAirportByCodeQuery, AirportDto?>
{
    private readonly IAirportReadRepository _readRepository;

    public GetAirportByCodeQueryHandler(IAirportReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<AirportDto?> Handle(GetAirportByCodeQuery request, CancellationToken ct)
        => _readRepository.GetByCodeAsync(request.Code, ct);
}
'@

Write-SourceFile "$app/Queries/GetAllAirports/GetAllAirportsQuery.cs" @'
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAllAirports;

public sealed record GetAllAirportsResult(IReadOnlyList<AirportDto> Items, int Total);

public sealed record GetAllAirportsQuery(int Page = 1, int PageSize = 100) : IRequest<GetAllAirportsResult>;
'@

Write-SourceFile "$app/Queries/GetAllAirports/GetAllAirportsQueryHandler.cs" @'
using FlightCatalog.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAllAirports;

public sealed class GetAllAirportsQueryHandler : IRequestHandler<GetAllAirportsQuery, GetAllAirportsResult>
{
    private readonly IAirportReadRepository _readRepository;

    public GetAllAirportsQueryHandler(IAirportReadRepository readRepository)
        => _readRepository = readRepository;

    public async Task<GetAllAirportsResult> Handle(GetAllAirportsQuery request, CancellationToken ct)
    {
        var (items, total) = await _readRepository.GetAllAsync(request.Page, request.PageSize, ct);
        return new GetAllAirportsResult(items, total);
    }
}
'@

# ===========================================================================
# 7. Application: Update FlightDto enrichment (replace read repo SQL)
# ===========================================================================
Write-Host ""
Write-Host "=== Application: enrich flight read repo (via Infrastructure update below) ==="

# ===========================================================================
# 8. Infrastructure: EF configuration for Airport
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: Airport EF configuration ==="

Write-SourceFile "$infra/Persistence/Configurations/AirportConfiguration.cs" @'
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FlightCatalog.Infrastructure.Persistence.Configurations;

public sealed class AirportConfiguration : IEntityTypeConfiguration<Airport>
{
    public void Configure(EntityTypeBuilder<Airport> builder)
    {
        builder.ToTable("airports");
        builder.HasKey(a => a.Id);
        builder.Property(a => a.Id).HasColumnName("id");

        builder.Property(a => a.Name).HasColumnName("name").HasMaxLength(200).IsRequired();
        builder.Property(a => a.City).HasColumnName("city").HasMaxLength(200).IsRequired();
        builder.Property(a => a.Timezone).HasColumnName("timezone").HasMaxLength(100).IsRequired();

        builder.ComplexProperty(a => a.Code, b =>
        {
            b.Property(x => x.Value).HasColumnName("airport_code").HasMaxLength(3).IsRequired();
        });

        builder.ComplexProperty(a => a.Coordinates, coords =>
        {
            coords.Property(c => c.Latitude).HasColumnName("latitude").IsRequired();
            coords.Property(c => c.Longitude).HasColumnName("longitude").IsRequired();
        });

        builder.HasIndex(a => a.Code).IsUnique();
    }
}
'@

# ===========================================================================
# 9. Infrastructure: Airport repositories
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: Airport repositories ==="

Write-SourceFile "$infra/Persistence/Repositories/AirportRepository.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

public sealed class AirportRepository : IAirportRepository
{
    private readonly FlightCatalogDbContext _db;

    public AirportRepository(FlightCatalogDbContext db) => _db = db;

    public Task<Airport?> GetByCodeAsync(AirportCode code, CancellationToken ct = default)
        => _db.Airports.FirstOrDefaultAsync(a => a.Code == code, ct);

    public async Task<IReadOnlyList<Airport>> GetAllAsync(CancellationToken ct = default)
        => await _db.Airports.ToListAsync(ct);

    public async Task AddAsync(Airport airport, CancellationToken ct = default)
        => await _db.Airports.AddAsync(airport, ct);

    public void Update(Airport airport) => _db.Airports.Update(airport);
}
'@

Write-SourceFile "$infra/Persistence/Repositories/AirportReadRepository.cs" @'
using Dapper;
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using Npgsql;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

public sealed class AirportReadRepository : IAirportReadRepository
{
    private readonly NpgsqlDataSource _dataSource;

    public AirportReadRepository(NpgsqlDataSource dataSource) => _dataSource = dataSource;

    public async Task<AirportDto?> GetByCodeAsync(string code, CancellationToken ct = default)
    {
        const string sql = @"
            SELECT id           AS Id,
                   airport_code AS Code,
                   name         AS Name,
                   city         AS City,
                   timezone     AS Timezone,
                   latitude     AS Latitude,
                   longitude    AS Longitude
            FROM flight_catalog.airports
            WHERE airport_code = @Code";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        return await conn.QueryFirstOrDefaultAsync<AirportDto>(
            new CommandDefinition(sql, new { Code = code.ToUpperInvariant() }, cancellationToken: ct));
    }

    public async Task<(IReadOnlyList<AirportDto> Items, int Total)> GetAllAsync(
        int page, int pageSize, CancellationToken ct = default)
    {
        if (page < 1) page = 1;
        if (pageSize < 1) pageSize = 100;
        if (pageSize > 500) pageSize = 500;

        const string sqlCount = "SELECT COUNT(*) FROM flight_catalog.airports";
        const string sqlPage = @"
            SELECT id           AS Id,
                   airport_code AS Code,
                   name         AS Name,
                   city         AS City,
                   timezone     AS Timezone,
                   latitude     AS Latitude,
                   longitude    AS Longitude
            FROM flight_catalog.airports
            ORDER BY airport_code
            OFFSET @Offset LIMIT @Limit";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        var total = await conn.ExecuteScalarAsync<int>(
            new CommandDefinition(sqlCount, cancellationToken: ct));

        var items = await conn.QueryAsync<AirportDto>(
            new CommandDefinition(sqlPage,
                new { Offset = (page - 1) * pageSize, Limit = pageSize },
                cancellationToken: ct));

        return (items.ToList(), total);
    }
}
'@

# ===========================================================================
# 10. Infrastructure: Bookings ACL
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: Bookings ACL ==="

Write-SourceFile "$infra/Integration/Bookings/BookingsAirportRow.cs" @'
namespace FlightCatalog.Infrastructure.Integration.Bookings;

internal sealed class BookingsAirportRow
{
    public string AirportCode { get; init; } = default!;
    public string AirportName { get; init; } = default!;
    public string City { get; init; } = default!;
    public string Timezone { get; init; } = default!;
    public string Coordinates { get; init; } = default!;
}
'@

Write-SourceFile "$infra/Integration/Bookings/BookingsSourceReader.cs" @'
using Dapper;
using FlightCatalog.Application.Abstractions;
using Npgsql;

namespace FlightCatalog.Infrastructure.Integration.Bookings;

internal sealed class BookingsSourceReader : IBookingsSourceReader
{
    private readonly NpgsqlDataSource _dataSource;

    public BookingsSourceReader(NpgsqlDataSource dataSource) => _dataSource = dataSource;

    public async Task<IReadOnlyList<ExternalAirport>> ReadAirportsAsync(CancellationToken ct = default)
    {
        const string sql = @"
            SELECT airport_code   AS AirportCode,
                   airport_name   AS AirportName,
                   city           AS City,
                   timezone       AS Timezone,
                   coordinates::text AS Coordinates
            FROM bookings.airports
            ORDER BY airport_code";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        var rows = await conn.QueryAsync<BookingsAirportRow>(
            new CommandDefinition(sql, cancellationToken: ct));

        return rows
            .Select(r => new ExternalAirport(
                r.AirportCode,
                r.AirportName,
                r.City,
                r.Timezone,
                r.Coordinates))
            .ToList();
    }
}
'@

# ===========================================================================
# 11. Infrastructure: Background service
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: AirportSyncBackgroundService ==="

Write-SourceFile "$infra/BackgroundServices/AirportSyncOptions.cs" @'
namespace FlightCatalog.Infrastructure.BackgroundServices;

public sealed class AirportSyncOptions
{
    public const string SectionName = "AirportSync";

    public bool Enabled { get; set; } = true;
    public int IntervalMinutes { get; set; } = 15;
    public bool SyncOnStartup { get; set; } = true;
}
'@

Write-SourceFile "$infra/BackgroundServices/AirportSyncBackgroundService.cs" @'
using FlightCatalog.Application.Commands.SyncAirports;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FlightCatalog.Infrastructure.BackgroundServices;

public sealed class AirportSyncBackgroundService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly AirportSyncOptions _options;
    private readonly ILogger<AirportSyncBackgroundService> _logger;

    public AirportSyncBackgroundService(
        IServiceScopeFactory scopeFactory,
        IOptions<AirportSyncOptions> options,
        ILogger<AirportSyncBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("Airport sync is disabled by configuration.");
            return;
        }

        _logger.LogInformation(
            "Airport sync started. Interval={Interval} min, SyncOnStartup={SyncOnStartup}",
            _options.IntervalMinutes, _options.SyncOnStartup);

        if (_options.SyncOnStartup)
        {
            await SafeSyncAsync(stoppingToken);
        }

        var interval = TimeSpan.FromMinutes(Math.Max(1, _options.IntervalMinutes));
        using var timer = new PeriodicTimer(interval);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken))
                    break;
                await SafeSyncAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        _logger.LogInformation("Airport sync stopped.");
    }

    private async Task SafeSyncAsync(CancellationToken ct)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
            await mediator.Send(new SyncAirportsCommand(), ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Airport sync iteration failed.");
        }
    }
}
'@

# ===========================================================================
# 12. Infrastructure: DbContext + DI updates
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: DbContext + DI updates ==="

Write-SourceFile "$infra/Persistence/FlightCatalogDbContext.cs" @'
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence;

public sealed class FlightCatalogDbContext : DbContext
{
    public const string SchemaName = "flight_catalog";

    public FlightCatalogDbContext(DbContextOptions<FlightCatalogDbContext> options)
        : base(options) { }

    public DbSet<Flight> Flights => Set<Flight>();
    public DbSet<Airport> Airports => Set<Airport>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(SchemaName);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FlightCatalogDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
'@

Write-SourceFile "$infra/DependencyInjection.cs" @'
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
            opts.UseNpgsql(ownConnection));

        // Own data source (read side)
        services.AddSingleton<NpgsqlDataSource>(sp => NpgsqlDataSource.Create(ownConnection));

        // External source data source (ACL read-only)
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

# ===========================================================================
# 13. FlightReadRepository: enrich with airport names
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: FlightReadRepository enriched ==="

Write-SourceFile "$infra/Persistence/Repositories/FlightReadRepository.cs" @'
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
            SELECT f.id                  AS Id,
                   f.flight_no           AS FlightNumber,
                   f.departure_airport   AS DepartureAirport,
                   dep.name              AS DepartureAirportName,
                   f.arrival_airport     AS ArrivalAirport,
                   arr.name              AS ArrivalAirportName,
                   f.scheduled_departure AS ScheduledDeparture,
                   f.scheduled_arrival   AS ScheduledArrival,
                   f.status              AS Status,
                   f.aircraft_model      AS AircraftModel
            FROM flight_catalog.flights f
            LEFT JOIN flight_catalog.airports dep ON dep.airport_code = f.departure_airport
            LEFT JOIN flight_catalog.airports arr ON arr.airport_code = f.arrival_airport
            WHERE f.id = @Id";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        return await conn.QueryFirstOrDefaultAsync<FlightDto>(
            new CommandDefinition(sql, new { Id = id }, cancellationToken: ct));
    }

    public async Task<IReadOnlyList<FlightDto>> SearchAsync(
        string from, string to, DateOnly date, CancellationToken ct = default)
    {
        const string sql = @"
            SELECT f.id                  AS Id,
                   f.flight_no           AS FlightNumber,
                   f.departure_airport   AS DepartureAirport,
                   dep.name              AS DepartureAirportName,
                   f.arrival_airport     AS ArrivalAirport,
                   arr.name              AS ArrivalAirportName,
                   f.scheduled_departure AS ScheduledDeparture,
                   f.scheduled_arrival   AS ScheduledArrival,
                   f.status              AS Status,
                   f.aircraft_model      AS AircraftModel
            FROM flight_catalog.flights f
            LEFT JOIN flight_catalog.airports dep ON dep.airport_code = f.departure_airport
            LEFT JOIN flight_catalog.airports arr ON arr.airport_code = f.arrival_airport
            WHERE f.departure_airport = @From
              AND f.arrival_airport   = @To
              AND f.scheduled_departure >= @StartOfDay
              AND f.scheduled_departure <  @EndOfDay
            ORDER BY f.scheduled_departure";

        var start = date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        var end = start.AddDays(1);

        await using var conn = await _dataSource.OpenConnectionAsync(ct);
        var rows = await conn.QueryAsync<FlightDto>(
            new CommandDefinition(sql,
                new
                {
                    From = from.ToUpperInvariant(),
                    To = to.ToUpperInvariant(),
                    StartOfDay = start,
                    EndOfDay = end
                },
                cancellationToken: ct));

        return rows.ToList();
    }
}
'@

# ===========================================================================
# 14. Api: Airport endpoints
# ===========================================================================
Write-Host ""
Write-Host "=== Api: Airport endpoints ==="

Write-SourceFile "$api/AirportEndpoints.cs" @'
using FlightCatalog.Application.Commands.SyncAirports;
using FlightCatalog.Application.Queries.GetAirportByCode;
using FlightCatalog.Application.Queries.GetAllAirports;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace FlightCatalog.Api;

public static class AirportEndpoints
{
    public static IEndpointRouteBuilder MapAirportEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/flight-catalog/airports").WithTags("Flight Catalog - Airports");

        group.MapGet("/{code}", async (
            string code,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetAirportByCodeQuery(code), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapGet("/", async (
            int? page,
            int? pageSize,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(
                new GetAllAirportsQuery(page ?? 1, pageSize ?? 100), ct);
            return Results.Ok(new
            {
                items = result.Items,
                total = result.Total,
                page = page ?? 1,
                pageSize = pageSize ?? 100
            });
        });

        group.MapPost("/sync", async (
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new SyncAirportsCommand(), ct);
            return result.IsSuccess
                ? Results.Ok(new
                {
                    read = result.Value!.Read,
                    created = result.Value.Created,
                    updated = result.Value.Updated,
                    skipped = result.Value.Skipped
                })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        return app;
    }
}
'@

# ===========================================================================
# 15. Host: appsettings + Program.cs
# ===========================================================================
Write-Host ""
Write-Host "=== Host: appsettings + Program.cs ==="

Write-SourceFile "$hostDir/appsettings.json" @'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "ConnectionStrings": {
    "FlightCatalog": "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password",
    "BookingsSource": "Host=127.0.0.1;Port=5433;Database=demo;Username=flights;Password=flights_dev_password;ApplicationName=FlightsPlatform.Sync"
  },
  "AirportSync": {
    "Enabled": true,
    "IntervalMinutes": 15,
    "SyncOnStartup": true
  },
  "AllowedHosts": "*"
}
'@

Write-SourceFile "$hostDir/Program.cs" @'
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

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await db.Database.EnsureCreatedAsync();
}

app.Run();
'@

# ===========================================================================
# 16. Tests
# ===========================================================================
Write-Host ""
Write-Host "=== Tests ==="

Write-SourceFile "$tests/Domain/CoordinatesTests.cs" @'
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class CoordinatesTests
{
    [Fact]
    public void Create_WithValidValues_Succeeds()
    {
        var c = Coordinates.Create(55.97, 37.41);
        c.Latitude.Should().Be(55.97);
        c.Longitude.Should().Be(37.41);
    }

    [Theory]
    [InlineData(91, 0)]
    [InlineData(-91, 0)]
    [InlineData(0, 181)]
    [InlineData(0, -181)]
    public void Create_OutOfRange_Throws(double lat, double lon)
    {
        var act = () => Coordinates.Create(lat, lon);
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void Parse_PostgresPointLiteral_Succeeds()
    {
        var c = Coordinates.Parse("(37.41,55.97)");
        c.Longitude.Should().BeApproximately(37.41, 0.0001);
        c.Latitude.Should().BeApproximately(55.97, 0.0001);
    }

    [Theory]
    [InlineData("")]
    [InlineData("garbage")]
    [InlineData("(1)")]
    public void Parse_Invalid_Throws(string raw)
    {
        var act = () => Coordinates.Parse(raw);
        act.Should().Throw<DomainException>();
    }
}
'@

Write-SourceFile "$tests/Domain/AirportTests.cs" @'
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class AirportTests
{
    private static Airport Make() =>
        Airport.Create(
            AirportCode.Create("SVO"),
            "Sheremetyevo",
            "Moscow",
            "Europe/Moscow",
            Coordinates.Create(55.97, 37.41));

    [Fact]
    public void Create_Valid_RaisesEvent()
    {
        var a = Make();
        a.DomainEvents.Should().ContainSingle(e => e is AirportSynced);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_EmptyName_Throws(string name)
    {
        var act = () => Airport.Create(
            AirportCode.Create("SVO"), name, "Moscow", "Europe/Moscow",
            Coordinates.Create(55.97, 37.41));
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void UpdateInfo_ChangesFields()
    {
        var a = Make();
        a.UpdateInfo("NewName", "NewCity", "UTC", Coordinates.Create(0, 0));
        a.Name.Should().Be("NewName");
        a.City.Should().Be("NewCity");
        a.Timezone.Should().Be("UTC");
    }
}
'@

Write-SourceFile "$tests/Application/SyncAirportsCommandHandlerTests.cs" @'
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.Commands.SyncAirports;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class SyncAirportsCommandHandlerTests
{
    [Fact]
    public async Task Handle_WithNewAirport_Creates()
    {
        var source = new Mock<IBookingsSourceReader>();
        source.Setup(s => s.ReadAirportsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<ExternalAirport>
            {
                new("SVO", "Sheremetyevo", "Moscow", "Europe/Moscow", "(37.41,55.97)")
            });

        var repo = new Mock<IAirportRepository>();
        repo.Setup(r => r.GetByCodeAsync(It.IsAny<AirportCode>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Airport?)null);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new SyncAirportsCommandHandler(
            source.Object, repo.Object, uow.Object,
            NullLogger<SyncAirportsCommandHandler>.Instance);

        var result = await handler.Handle(new SyncAirportsCommand(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Created.Should().Be(1);
        result.Value.Updated.Should().Be(0);
        repo.Verify(r => r.AddAsync(It.IsAny<Airport>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_WithExistingAirport_Updates()
    {
        var existing = Airport.Create(
            AirportCode.Create("SVO"), "Old", "OldCity", "UTC",
            Coordinates.Create(0, 0));

        var source = new Mock<IBookingsSourceReader>();
        source.Setup(s => s.ReadAirportsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<ExternalAirport>
            {
                new("SVO", "NewName", "NewCity", "Europe/Moscow", "(37.41,55.97)")
            });

        var repo = new Mock<IAirportRepository>();
        repo.Setup(r => r.GetByCodeAsync(It.IsAny<AirportCode>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(existing);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new SyncAirportsCommandHandler(
            source.Object, repo.Object, uow.Object,
            NullLogger<SyncAirportsCommandHandler>.Instance);

        var result = await handler.Handle(new SyncAirportsCommand(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Updated.Should().Be(1);
        result.Value.Created.Should().Be(0);
        existing.Name.Should().Be("NewName");
    }

    [Fact]
    public async Task Handle_WithInvalidCoordinates_Skips()
    {
        var source = new Mock<IBookingsSourceReader>();
        source.Setup(s => s.ReadAirportsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<ExternalAirport>
            {
                new("BAD", "Bad", "Nowhere", "UTC", "not-a-point")
            });

        var repo = new Mock<IAirportRepository>();
        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(0);

        var handler = new SyncAirportsCommandHandler(
            source.Object, repo.Object, uow.Object,
            NullLogger<SyncAirportsCommandHandler>.Instance);

        var result = await handler.Handle(new SyncAirportsCommand(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Skipped.Should().Be(1);
    }
}
'@

# ===========================================================================
# 17. ADR-004
# ===========================================================================
Write-Host ""
Write-Host "=== ADR-004 ==="

Write-SourceFile "$docs/ADR-004-integration-acl-polling.md" @'
# ADR-004: Integration with external source via ACL and polling sync

## Status
Accepted

## Context
The platform must integrate with an external legacy database (Postgres `demo`
with schema `bookings`) that we do not own. We need reference data (airports)
from that system, but we must not couple our domain to its schema, naming,
or lifecycle. Cross-database joins are not possible in Postgres.

## Decision
1. Keep our own database (`flights_demo`) and schema (`flight_catalog`).
2. Integrate via an Anti-Corruption Layer (ACL):
   - `IBookingsSourceReader` lives in the Application layer (contract);
   - its implementation `BookingsSourceReader` lives in Infrastructure
     and is `internal`;
   - a separate connection string `BookingsSource` is used, read-only,
     with `ApplicationName=FlightsPlatform.Sync`.
3. Synchronize reference data (airports) via a background polling service
   (`AirportSyncBackgroundService`), with configurable interval and startup
   behavior.
4. The domain never references external column names or schemas.

## Consequences
Positive:
- Domain is isolated from the external system.
- Renaming a column in the source only requires changes in ACL.
- We can later swap the source (Kafka topic, REST API) without touching
  the domain.

Negative:
- Eventual consistency: our copy of airports may lag behind the source.
- Polling overhead (acceptable: reference data changes rarely).

## Alternatives considered
- **Direct cross-database join** - not possible in Postgres.
- **Postgres FDW (Foreign Data Wrapper)** - works, but adds infrastructure
  complexity and couples us to the source schema anyway.
- **CDC (Debezium + Kafka)** - correct for high-churn data; overkill for
  airports that change a few times a year. Planned for phase 5.
'@

# ===========================================================================
# 18. Clean + build + test
# ===========================================================================
Write-Host ""
Write-Host "=== Clean + build + test ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED - see errors above" -ForegroundColor Red
    exit 1
}

dotnet test --no-build --nologo

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  1. dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  2. Watch logs: AirportSyncBackgroundService will sync airports on startup"
Write-Host "  3. Open https://localhost:50943/scalar/v1"
Write-Host "  4. Try: GET /flight-catalog/airports/SVO"
Write-Host "  5. Try: POST /flight-catalog/airports/sync"
Write-Host "  6. Verify in pgAdmin (database flights_demo):"
Write-Host "     SELECT COUNT(*) FROM flight_catalog.airports;"
Write-Host ""
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
    private readonly ICacheService _cache;
    private readonly ILogger<SyncAirportsCommandHandler> _logger;

    public SyncAirportsCommandHandler(
        IBookingsSourceReader source,
        IAirportRepository repository,
        IUnitOfWork unitOfWork,
        ICacheService cache,
        ILogger<SyncAirportsCommandHandler> logger)
    {
        _source = source;
        _repository = repository;
        _unitOfWork = unitOfWork;
        _cache = cache;
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

        // Invalidate all airport cache entries: reference data changed.
        await _cache.RemoveByPrefixAsync(CacheKeys.AirportPrefix, ct);
        _logger.LogInformation("Airport cache invalidated after sync");

        var result = new SyncAirportsResult(external.Count, created, updated, skipped);
        _logger.LogInformation(
            "Airport sync complete: read={Read}, created={Created}, updated={Updated}, skipped={Skipped}",
            result.Read, result.Created, result.Updated, result.Skipped);

        return Result<SyncAirportsResult>.Success(result);
    }
}
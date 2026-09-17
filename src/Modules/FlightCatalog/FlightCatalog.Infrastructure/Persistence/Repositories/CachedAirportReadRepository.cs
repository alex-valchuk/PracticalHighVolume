using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using FlightsPlatform.Application.Abstractions;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

/// <summary>
/// Cache-aside decorator for airport reads.
/// Wraps the Dapper-based repository: on hit, returns from Redis; on miss,
/// queries the source and stores the result with a TTL.
/// Redis failures degrade to source-of-truth reads.
/// </summary>
internal sealed class CachedAirportReadRepository : IAirportReadRepository
{
    private static readonly TimeSpan Ttl = TimeSpan.FromMinutes(15);

    private readonly IAirportReadRepository _inner;
    private readonly ICacheService _cache;
    private readonly ILogger<CachedAirportReadRepository> _logger;

    public CachedAirportReadRepository(
        IAirportReadRepository inner,
        ICacheService cache,
        ILogger<CachedAirportReadRepository> logger)
    {
        _inner = inner;
        _cache = cache;
        _logger = logger;
    }

    public async Task<AirportDto?> GetByCodeAsync(string code, CancellationToken ct = default)
    {
        var key = CacheKeys.Airport(code);

        var cached = await _cache.GetAsync<AirportDto>(key, ct);
        if (cached is not null)
        {
            _logger.LogDebug("Cache HIT for airport {Code}", code);
            return cached;
        }

        var dto = await _inner.GetByCodeAsync(code, ct);
        if (dto is not null)
        {
            await _cache.SetAsync(key, dto, Ttl, ct);
        }

        return dto;
    }

    public async Task<(IReadOnlyList<AirportDto> Items, int Total)> GetAllAsync(
        int page, int pageSize, CancellationToken ct = default)
    {
        // List reads are not cached: aggregates change with every sync,
        // and every UI search hits the DB anyway. Only point lookups are cached.
        return await _inner.GetAllAsync(page, pageSize, ct);
    }
}
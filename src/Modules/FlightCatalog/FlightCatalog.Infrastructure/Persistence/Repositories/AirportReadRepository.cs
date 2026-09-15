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
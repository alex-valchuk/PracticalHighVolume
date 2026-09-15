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
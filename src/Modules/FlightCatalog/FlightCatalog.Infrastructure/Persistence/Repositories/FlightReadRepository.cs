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
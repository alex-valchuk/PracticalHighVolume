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
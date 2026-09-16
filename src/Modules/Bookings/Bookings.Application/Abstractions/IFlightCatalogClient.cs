namespace Bookings.Application.Abstractions;

/// <summary>
/// Contract for synchronous queries to the FlightCatalog module.
/// Implementation lives in Bookings.Infrastructure and calls FlightCatalog
/// via IMediator. Declared here so that Bookings.Application does not
/// reference FlightCatalog.Application directly.
/// </summary>
public interface IFlightCatalogClient
{
    Task<FlightSummary?> GetFlightAsync(Guid flightId, CancellationToken ct = default);
}

public sealed record FlightSummary(
    Guid Id,
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset ScheduledDeparture,
    DateTimeOffset ScheduledArrival,
    int Status);
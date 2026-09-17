using FlightsPlatform.Contracts.Common;

namespace FlightsPlatform.Contracts.FlightCatalog;

public sealed record FlightScheduledIntegrationEvent : IntegrationEventBase
{
    public Guid FlightId { get; init; }
    public string FlightNumber { get; init; } = default!;
    public string DepartureAirport { get; init; } = default!;
    public string ArrivalAirport { get; init; } = default!;
    public DateTimeOffset ScheduledDeparture { get; init; }
    public DateTimeOffset ScheduledArrival { get; init; }
}
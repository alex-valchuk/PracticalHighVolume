using FlightsPlatform.Contracts.Common;

namespace FlightsPlatform.Contracts.FlightCatalog;

public sealed record FlightDelayedIntegrationEvent : IntegrationEventBase
{
    public Guid FlightId { get; init; }
    public string FlightNumber { get; init; } = default!;
    public DateTimeOffset OldDeparture { get; init; }
    public DateTimeOffset NewDeparture { get; init; }
    public bool IsSignificant { get; init; }
}
using FlightsPlatform.Contracts.Common;

namespace FlightsPlatform.Contracts.FlightCatalog;

public sealed record FlightCancelledIntegrationEvent : IntegrationEventBase
{
    public Guid FlightId { get; init; }
    public string FlightNumber { get; init; } = default!;
    public string Reason { get; init; } = default!;
}
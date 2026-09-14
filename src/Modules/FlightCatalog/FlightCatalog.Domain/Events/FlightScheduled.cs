using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record FlightScheduled(
    Guid FlightId,
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset Departure,
    DateTimeOffset Arrival) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
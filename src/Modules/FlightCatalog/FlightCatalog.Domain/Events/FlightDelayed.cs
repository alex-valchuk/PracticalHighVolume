using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record FlightDelayed(
    Guid FlightId,
    string FlightNumber,
    DateTimeOffset OldDeparture,
    DateTimeOffset NewDeparture,
    bool IsSignificant) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
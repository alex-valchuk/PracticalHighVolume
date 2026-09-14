using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record FlightCancelled(
    Guid FlightId,
    string FlightNumber,
    string Reason) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
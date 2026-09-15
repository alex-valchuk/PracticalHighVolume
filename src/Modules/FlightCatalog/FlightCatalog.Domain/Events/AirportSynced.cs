using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Events;

public sealed record AirportSynced(
    Guid AirportId,
    string Code,
    string Name,
    string City) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
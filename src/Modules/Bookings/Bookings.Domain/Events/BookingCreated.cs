using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingCreated(
    Guid BookingId,
    string BookingReference,
    string PassengerId,
    string Currency) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
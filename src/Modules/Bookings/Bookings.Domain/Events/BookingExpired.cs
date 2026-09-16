using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingExpired(
    Guid BookingId,
    string BookingReference,
    string Reason) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
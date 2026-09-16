using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingConfirmed(
    Guid BookingId,
    string BookingReference,
    decimal TotalAmount,
    string Currency) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
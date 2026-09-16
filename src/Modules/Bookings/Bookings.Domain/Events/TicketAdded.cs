using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record TicketAdded(
    Guid BookingId,
    Guid TicketId,
    Guid FlightId,
    decimal Amount,
    string Currency) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
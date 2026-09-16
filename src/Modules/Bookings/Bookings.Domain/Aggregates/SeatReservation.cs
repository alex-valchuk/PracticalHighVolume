using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class SeatReservation : Entity<Guid>
{
    public Guid BookingId { get; private set; }
    public Guid TicketId { get; private set; }
    public Guid FlightId { get; private set; }
    public SeatReservationStatus Status { get; private set; }
    public DateTimeOffset ReservedAt { get; private set; }
    public DateTimeOffset? ReleasedAt { get; private set; }

    private SeatReservation() { }

    private SeatReservation(Guid id, Guid bookingId, Guid ticketId, Guid flightId) : base(id)
    {
        BookingId = bookingId;
        TicketId = ticketId;
        FlightId = flightId;
        Status = SeatReservationStatus.Active;
        ReservedAt = DateTimeOffset.UtcNow;
    }

    public static SeatReservation Create(Guid bookingId, Guid ticketId, Guid flightId)
    {
        if (bookingId == Guid.Empty) throw new DomainException("BookingId is required.");
        if (ticketId == Guid.Empty) throw new DomainException("TicketId is required.");
        if (flightId == Guid.Empty) throw new DomainException("FlightId is required.");

        return new SeatReservation(Guid.NewGuid(), bookingId, ticketId, flightId);
    }

    public void Release()
    {
        if (Status == SeatReservationStatus.Released) return;
        Status = SeatReservationStatus.Released;
        ReleasedAt = DateTimeOffset.UtcNow;
    }
}
namespace Bookings.Application.Abstractions;

public interface ISeatReservationService
{
    Task<Guid> ReserveAsync(Guid bookingId, Guid ticketId, Guid flightId, CancellationToken ct = default);
    Task ReleaseAsync(Guid reservationId, CancellationToken ct = default);
    Task ReleaseAllForBookingAsync(Guid bookingId, CancellationToken ct = default);
}
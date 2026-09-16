using Bookings.Application.Abstractions;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Bookings.Infrastructure.Persistence.Services;

internal sealed class SeatReservationService : ISeatReservationService
{
    private readonly BookingDbContext _db;
    private readonly ILogger<SeatReservationService> _logger;

    public SeatReservationService(BookingDbContext db, ILogger<SeatReservationService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<Guid> ReserveAsync(
        Guid bookingId, Guid ticketId, Guid flightId, CancellationToken ct = default)
    {
        var reservation = SeatReservation.Create(bookingId, ticketId, flightId);
        _db.Set<SeatReservation>().Add(reservation);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "SeatReservationService: reserved {ReservationId} for booking={BookingId} ticket={TicketId} flight={FlightId}",
            reservation.Id, bookingId, ticketId, flightId);

        return reservation.Id;
    }

    public async Task ReleaseAsync(Guid reservationId, CancellationToken ct = default)
    {
        var reservation = await _db.Set<SeatReservation>()
            .FirstOrDefaultAsync(r => r.Id == reservationId, ct);

        if (reservation is null)
        {
            _logger.LogWarning("SeatReservationService: reservation {ReservationId} not found", reservationId);
            return;
        }

        reservation.Release();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("SeatReservationService: released {ReservationId}", reservationId);
    }

    public async Task ReleaseAllForBookingAsync(Guid bookingId, CancellationToken ct = default)
    {
        var active = await _db.Set<SeatReservation>()
            .Where(r => r.BookingId == bookingId && r.Status == SeatReservationStatus.Active)
            .ToListAsync(ct);

        if (active.Count == 0) return;

        foreach (var r in active) r.Release();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "SeatReservationService: released {Count} reservations for booking={BookingId}",
            active.Count, bookingId);
    }
}
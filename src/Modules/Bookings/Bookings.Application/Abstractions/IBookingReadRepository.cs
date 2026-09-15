using Bookings.Application.DTOs;

namespace Bookings.Application.Abstractions;

public interface IBookingReadRepository
{
    Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default);
}
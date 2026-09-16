using Bookings.Application.DTOs;

namespace Bookings.Application.Abstractions;

public interface IBookingReadRepository
{
    Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<(IReadOnlyList<BookingDto> Items, int Total)> GetAllAsync(
        int page, int pageSize, CancellationToken ct = default);
}
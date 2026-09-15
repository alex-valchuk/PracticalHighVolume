using Bookings.Application.Abstractions;
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace Bookings.Infrastructure.Persistence.Repositories;

public sealed class BookingRepository : IBookingRepository
{
    private readonly BookingDbContext _db;

    public BookingRepository(BookingDbContext db) => _db = db;

    public Task<Booking?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => _db.Bookings.FirstOrDefaultAsync(b => b.Id == id, ct);

    public async Task AddAsync(Booking booking, CancellationToken ct = default)
        => await _db.Bookings.AddAsync(booking, ct);

    public void Update(Booking booking) => _db.Bookings.Update(booking);
}
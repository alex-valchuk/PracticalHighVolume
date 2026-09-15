using Bookings.Application.Abstractions;

namespace Bookings.Infrastructure.Persistence;

public sealed class UnitOfWork : IUnitOfWork
{
    private readonly BookingDbContext _db;

    public UnitOfWork(BookingDbContext db) => _db = db;

    public Task<int> SaveChangesAsync(CancellationToken ct = default) => _db.SaveChangesAsync(ct);
}
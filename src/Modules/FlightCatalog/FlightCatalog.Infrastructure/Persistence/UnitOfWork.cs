using FlightCatalog.Application.Abstractions;

namespace FlightCatalog.Infrastructure.Persistence;

public sealed class UnitOfWork : IUnitOfWork
{
    private readonly FlightCatalogDbContext _db;

    public UnitOfWork(FlightCatalogDbContext db) => _db = db;

    public Task<int> SaveChangesAsync(CancellationToken ct = default) => _db.SaveChangesAsync(ct);
}
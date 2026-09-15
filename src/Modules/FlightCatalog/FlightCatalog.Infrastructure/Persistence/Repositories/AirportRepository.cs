using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

public sealed class AirportRepository : IAirportRepository
{
    private readonly FlightCatalogDbContext _db;

    public AirportRepository(FlightCatalogDbContext db) => _db = db;

    public Task<Airport?> GetByCodeAsync(AirportCode code, CancellationToken ct = default)
        => _db.Airports.FirstOrDefaultAsync(a => a.Code == code, ct);

    public async Task<IReadOnlyList<Airport>> GetAllAsync(CancellationToken ct = default)
        => await _db.Airports.ToListAsync(ct);

    public async Task AddAsync(Airport airport, CancellationToken ct = default)
        => await _db.Airports.AddAsync(airport, ct);

    public void Update(Airport airport) => _db.Airports.Update(airport);
}
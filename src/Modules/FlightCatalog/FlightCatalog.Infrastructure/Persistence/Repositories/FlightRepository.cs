using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence.Repositories;

public sealed class FlightRepository : IFlightRepository
{
    private readonly FlightCatalogDbContext _db;

    public FlightRepository(FlightCatalogDbContext db) => _db = db;

    public Task<Flight?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => _db.Flights.FirstOrDefaultAsync(f => f.Id == id, ct);

    public async Task AddAsync(Flight flight, CancellationToken ct = default)
        => await _db.Flights.AddAsync(flight, ct);

    public void Update(Flight flight) => _db.Flights.Update(flight);
}
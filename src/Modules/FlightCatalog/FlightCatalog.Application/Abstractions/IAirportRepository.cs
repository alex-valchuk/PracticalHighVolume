using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;

namespace FlightCatalog.Application.Abstractions;

public interface IAirportRepository
{
    Task<Airport?> GetByCodeAsync(AirportCode code, CancellationToken ct = default);
    Task<IReadOnlyList<Airport>> GetAllAsync(CancellationToken ct = default);
    Task AddAsync(Airport airport, CancellationToken ct = default);
    void Update(Airport airport);
}
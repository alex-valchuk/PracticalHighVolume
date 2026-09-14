using FlightCatalog.Domain.Aggregates;

namespace FlightCatalog.Application.Abstractions;

public interface IFlightRepository
{
    Task<Flight?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task AddAsync(Flight flight, CancellationToken ct = default);
    void Update(Flight flight);
}
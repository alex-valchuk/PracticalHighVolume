using FlightCatalog.Application.DTOs;

namespace FlightCatalog.Application.Abstractions;

public interface IFlightReadRepository
{
    Task<FlightDto?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<IReadOnlyList<FlightDto>> SearchAsync(string from, string to, DateOnly date, CancellationToken ct = default);
}
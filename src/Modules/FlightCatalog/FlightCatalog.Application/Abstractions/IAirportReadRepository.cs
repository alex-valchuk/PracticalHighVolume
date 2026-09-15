using FlightCatalog.Application.DTOs;

namespace FlightCatalog.Application.Abstractions;

public interface IAirportReadRepository
{
    Task<AirportDto?> GetByCodeAsync(string code, CancellationToken ct = default);
    Task<(IReadOnlyList<AirportDto> Items, int Total)> GetAllAsync(int page, int pageSize, CancellationToken ct = default);
}
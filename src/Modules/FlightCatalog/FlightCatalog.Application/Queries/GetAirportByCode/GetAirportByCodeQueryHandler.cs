using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAirportByCode;

public sealed class GetAirportByCodeQueryHandler : IRequestHandler<GetAirportByCodeQuery, AirportDto?>
{
    private readonly IAirportReadRepository _readRepository;

    public GetAirportByCodeQueryHandler(IAirportReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<AirportDto?> Handle(GetAirportByCodeQuery request, CancellationToken ct)
        => _readRepository.GetByCodeAsync(request.Code, ct);
}
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetFlightById;

public sealed class GetFlightByIdQueryHandler : IRequestHandler<GetFlightByIdQuery, FlightDto?>
{
    private readonly IFlightReadRepository _readRepository;

    public GetFlightByIdQueryHandler(IFlightReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<FlightDto?> Handle(GetFlightByIdQuery request, CancellationToken ct)
        => _readRepository.GetByIdAsync(request.FlightId, ct);
}
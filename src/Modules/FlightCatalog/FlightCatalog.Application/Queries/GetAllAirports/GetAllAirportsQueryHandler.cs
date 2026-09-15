using FlightCatalog.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAllAirports;

public sealed class GetAllAirportsQueryHandler : IRequestHandler<GetAllAirportsQuery, GetAllAirportsResult>
{
    private readonly IAirportReadRepository _readRepository;

    public GetAllAirportsQueryHandler(IAirportReadRepository readRepository)
        => _readRepository = readRepository;

    public async Task<GetAllAirportsResult> Handle(GetAllAirportsQuery request, CancellationToken ct)
    {
        var (items, total) = await _readRepository.GetAllAsync(request.Page, request.PageSize, ct);
        return new GetAllAirportsResult(items, total);
    }
}
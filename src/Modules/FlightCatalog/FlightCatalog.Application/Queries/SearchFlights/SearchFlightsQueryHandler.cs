using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.SearchFlights;

public sealed class SearchFlightsQueryHandler : IRequestHandler<SearchFlightsQuery, IReadOnlyList<FlightDto>>
{
    private readonly IFlightReadRepository _readRepository;

    public SearchFlightsQueryHandler(IFlightReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<IReadOnlyList<FlightDto>> Handle(SearchFlightsQuery request, CancellationToken ct)
        => _readRepository.SearchAsync(request.From, request.To, request.Date, ct);
}
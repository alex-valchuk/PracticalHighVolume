using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.SearchFlights;

public sealed record SearchFlightsQuery(
    string From,
    string To,
    DateOnly Date) : IRequest<IReadOnlyList<FlightDto>>;
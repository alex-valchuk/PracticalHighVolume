using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAllAirports;

public sealed record GetAllAirportsResult(IReadOnlyList<AirportDto> Items, int Total);

public sealed record GetAllAirportsQuery(int Page = 1, int PageSize = 100) : IRequest<GetAllAirportsResult>;
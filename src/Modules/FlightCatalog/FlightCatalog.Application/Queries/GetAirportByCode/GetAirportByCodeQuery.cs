using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetAirportByCode;

public sealed record GetAirportByCodeQuery(string Code) : IRequest<AirportDto?>;
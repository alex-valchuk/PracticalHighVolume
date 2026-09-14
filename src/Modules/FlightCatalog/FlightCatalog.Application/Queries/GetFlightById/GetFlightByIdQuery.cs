using FlightCatalog.Application.DTOs;
using MediatR;

namespace FlightCatalog.Application.Queries.GetFlightById;

public sealed record GetFlightByIdQuery(Guid FlightId) : IRequest<FlightDto?>;
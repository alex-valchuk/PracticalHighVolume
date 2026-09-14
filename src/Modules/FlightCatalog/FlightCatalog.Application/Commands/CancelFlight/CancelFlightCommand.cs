using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed record CancelFlightCommand(Guid FlightId, string Reason) : IRequest<Result>;
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.DelayFlight;

public sealed record DelayFlightCommand(
    Guid FlightId,
    DateTimeOffset NewDeparture,
    DateTimeOffset NewArrival) : IRequest<Result>;
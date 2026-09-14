using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.ScheduleFlight;

public sealed record ScheduleFlightCommand(
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset Departure,
    DateTimeOffset Arrival,
    string AircraftModel) : IRequest<Result<Guid>>;
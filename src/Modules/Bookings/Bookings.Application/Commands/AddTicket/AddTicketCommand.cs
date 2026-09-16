using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.AddTicket;

public sealed record AddTicketCommand(
    Guid BookingId,
    Guid FlightId,
    string PassengerId,
    string PassengerName,
    decimal Amount) : IRequest<Result<Guid>>;
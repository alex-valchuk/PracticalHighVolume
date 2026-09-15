using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.CreateBooking;

public sealed record CreateBookingCommand(
    string PassengerId,
    string PassengerName,
    string Currency) : IRequest<Result<Guid>>;
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.CancelBooking;

public sealed record CancelBookingCommand(Guid BookingId, string Reason) : IRequest<Result>;
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.ConfirmBooking;

public sealed record ConfirmBookingResult(Guid BookingId, bool Confirmed, string? FailureReason);

public sealed record ConfirmBookingCommand(Guid BookingId) : IRequest<Result<ConfirmBookingResult>>;
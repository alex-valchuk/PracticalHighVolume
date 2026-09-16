using FluentValidation;

namespace Bookings.Application.Commands.ConfirmBooking;

public sealed class ConfirmBookingCommandValidator : AbstractValidator<ConfirmBookingCommand>
{
    public ConfirmBookingCommandValidator()
    {
        RuleFor(x => x.BookingId).NotEmpty();
    }
}
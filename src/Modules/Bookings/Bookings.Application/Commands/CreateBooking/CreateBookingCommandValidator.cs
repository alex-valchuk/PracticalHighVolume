using FluentValidation;

namespace Bookings.Application.Commands.CreateBooking;

public sealed class CreateBookingCommandValidator : AbstractValidator<CreateBookingCommand>
{
    public CreateBookingCommandValidator()
    {
        RuleFor(x => x.PassengerId).NotEmpty().Length(5, 20);
        RuleFor(x => x.PassengerName).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Currency).NotEmpty().Length(3);
    }
}
using FluentValidation;

namespace Bookings.Application.Commands.AddTicket;

public sealed class AddTicketCommandValidator : AbstractValidator<AddTicketCommand>
{
    public AddTicketCommandValidator()
    {
        RuleFor(x => x.BookingId).NotEmpty();
        RuleFor(x => x.FlightId).NotEmpty();
        RuleFor(x => x.PassengerId).NotEmpty().Length(5, 20);
        RuleFor(x => x.PassengerName).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Amount).GreaterThan(0);
    }
}
using FluentValidation;

namespace FlightCatalog.Application.Commands.DelayFlight;

public sealed class DelayFlightCommandValidator : AbstractValidator<DelayFlightCommand>
{
    public DelayFlightCommandValidator()
    {
        RuleFor(x => x.FlightId).NotEmpty();
        RuleFor(x => x.NewDeparture).NotEmpty();
        RuleFor(x => x.NewArrival).NotEmpty().GreaterThan(x => x.NewDeparture);
    }
}
using FluentValidation;

namespace FlightCatalog.Application.Commands.ScheduleFlight;

public sealed class ScheduleFlightCommandValidator : AbstractValidator<ScheduleFlightCommand>
{
    public ScheduleFlightCommandValidator()
    {
        RuleFor(x => x.FlightNumber).NotEmpty().MaximumLength(10);
        RuleFor(x => x.DepartureAirport).NotEmpty().Length(3);
        RuleFor(x => x.ArrivalAirport).NotEmpty().Length(3);
        RuleFor(x => x.Departure).NotEmpty();
        RuleFor(x => x.Arrival).NotEmpty().GreaterThan(x => x.Departure);
        RuleFor(x => x.AircraftModel).NotEmpty().MaximumLength(100);
    }
}
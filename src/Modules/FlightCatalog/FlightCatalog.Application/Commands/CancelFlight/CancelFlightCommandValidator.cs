using FluentValidation;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed class CancelFlightCommandValidator : AbstractValidator<CancelFlightCommand>
{
    public CancelFlightCommandValidator()
    {
        RuleFor(x => x.FlightId).NotEmpty();
        RuleFor(x => x.Reason).NotEmpty().MaximumLength(500);
    }
}
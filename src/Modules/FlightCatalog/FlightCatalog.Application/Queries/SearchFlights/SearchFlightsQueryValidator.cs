using FluentValidation;

namespace FlightCatalog.Application.Queries.SearchFlights;

public sealed class SearchFlightsQueryValidator : AbstractValidator<SearchFlightsQuery>
{
    public SearchFlightsQueryValidator()
    {
        RuleFor(x => x.From).NotEmpty().Length(3);
        RuleFor(x => x.To).NotEmpty().Length(3);
        RuleFor(x => x.Date).NotEmpty();
    }
}
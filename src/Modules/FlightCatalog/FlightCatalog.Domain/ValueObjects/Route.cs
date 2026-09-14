using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Route : ValueObject
{
    public AirportCode Departure { get; private set; } = default!;
    public AirportCode Arrival { get; private set; } = default!;

    private Route() { }

    private Route(AirportCode departure, AirportCode arrival)
    {
        Departure = departure;
        Arrival = arrival;
    }

    public static Route Create(AirportCode departure, AirportCode arrival)
    {
        if (departure == arrival)
            throw new DomainException("Departure and arrival airports must be different.");

        return new Route(departure, arrival);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Departure;
        yield return Arrival;
    }
}
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Schedule : ValueObject
{
    public DateTimeOffset Departure { get; private set; }
    public DateTimeOffset Arrival { get; private set; }

    private Schedule() { }

    private Schedule(DateTimeOffset departure, DateTimeOffset arrival)
    {
        Departure = departure;
        Arrival = arrival;
    }

    public static Schedule Create(DateTimeOffset departure, DateTimeOffset arrival)
    {
        if (arrival <= departure)
            throw new DomainException("Arrival must be after departure.");

        return new Schedule(departure, arrival);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Departure;
        yield return Arrival;
    }
}
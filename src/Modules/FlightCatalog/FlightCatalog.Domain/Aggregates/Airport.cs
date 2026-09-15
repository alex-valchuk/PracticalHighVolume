using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Aggregates;

public sealed class Airport : AggregateRoot<Guid>
{
    public AirportCode Code { get; private set; } = default!;
    public string Name { get; private set; } = default!;
    public string City { get; private set; } = default!;
    public string Timezone { get; private set; } = default!;
    public Coordinates Coordinates { get; private set; } = default!;

    private Airport() { }

    private Airport(Guid id, AirportCode code, string name, string city, string timezone, Coordinates coordinates)
        : base(id)
    {
        Code = code;
        Name = name;
        City = city;
        Timezone = timezone;
        Coordinates = coordinates;
    }

    public static Airport Create(
        AirportCode code,
        string name,
        string city,
        string timezone,
        Coordinates coordinates)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Airport name is required.");
        if (string.IsNullOrWhiteSpace(city))
            throw new DomainException("City is required.");
        if (string.IsNullOrWhiteSpace(timezone))
            throw new DomainException("Timezone is required.");

        var airport = new Airport(Guid.NewGuid(), code, name.Trim(), city.Trim(), timezone.Trim(), coordinates);

        airport.Raise(new AirportSynced(airport.Id, code.Value, name, city));

        return airport;
    }

    public void UpdateInfo(string name, string city, string timezone, Coordinates coordinates)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Airport name is required.");
        if (string.IsNullOrWhiteSpace(city))
            throw new DomainException("City is required.");
        if (string.IsNullOrWhiteSpace(timezone))
            throw new DomainException("Timezone is required.");

        Name = name.Trim();
        City = city.Trim();
        Timezone = timezone.Trim();
        Coordinates = coordinates;
    }
}
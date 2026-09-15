using System.Globalization;
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class Coordinates : ValueObject
{
    public double Latitude { get; private set; }
    public double Longitude { get; private set; }

    private Coordinates() { }

    private Coordinates(double latitude, double longitude)
    {
        Latitude = latitude;
        Longitude = longitude;
    }

    public static Coordinates Create(double latitude, double longitude)
    {
        if (latitude < -90 || latitude > 90)
            throw new DomainException("Latitude must be in range [-90, 90].");
        if (longitude < -180 || longitude > 180)
            throw new DomainException("Longitude must be in range [-180, 180].");

        return new Coordinates(latitude, longitude);
    }

    // Parses Postgres point literal "(lon,lat)" -> Coordinates(lat, lon)
    public static Coordinates Parse(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            throw new DomainException("Coordinates string is empty.");

        var trimmed = raw.Trim();
        if (trimmed.StartsWith("(") && trimmed.EndsWith(")"))
            trimmed = trimmed[1..^1];

        var parts = trimmed.Split(',');
        if (parts.Length != 2)
            throw new DomainException("Invalid coordinates format: " + raw);

        if (!double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var lon))
            throw new DomainException("Invalid longitude in: " + raw);
        if (!double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var lat))
            throw new DomainException("Invalid latitude in: " + raw);

        return Create(lat, lon);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Latitude;
        yield return Longitude;
    }

    public override string ToString()
        => string.Format(CultureInfo.InvariantCulture, "({0},{1})", Longitude, Latitude);
}
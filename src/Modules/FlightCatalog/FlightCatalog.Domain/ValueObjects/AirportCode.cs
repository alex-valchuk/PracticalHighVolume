using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class AirportCode : ValueObject
{
    public string Value { get; private set; } = default!;

    private AirportCode() { }

    private AirportCode(string value) => Value = value;

    public static AirportCode Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Airport code cannot be empty");

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length != 3 || !normalized.All(char.IsLetter))
            throw new DomainException("Airport code must be exactly 3 letters. Got: " + value);

        return new AirportCode(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
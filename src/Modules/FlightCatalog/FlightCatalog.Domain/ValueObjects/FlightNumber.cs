using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.ValueObjects;

public sealed class FlightNumber : ValueObject
{
    public string Value { get; private set; } = default!;

    private FlightNumber() { }

    private FlightNumber(string value) => Value = value;

    public static FlightNumber Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Flight number cannot be empty");

        var normalized = value.Trim().ToUpperInvariant();
        var parts = normalized.Split('-');

        if (parts.Length != 2
            || parts[0].Length != 2 || !parts[0].All(char.IsLetter)
            || parts[1].Length < 1 || parts[1].Length > 4 || !parts[1].All(char.IsDigit))
        {
            throw new DomainException("Invalid flight number " + value + ". Expected format XX-NNNN.");
        }

        return new FlightNumber(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class PassengerName : ValueObject
{
    public string Value { get; private set; } = default!;

    private PassengerName() { }
    private PassengerName(string value) => Value = value;

    public static PassengerName Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Passenger name cannot be empty.");

        var normalized = value.Trim();
        if (normalized.Length > 200)
            throw new DomainException("Passenger name is too long.");

        return new PassengerName(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
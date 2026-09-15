using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class PassengerId : ValueObject
{
    public string Value { get; private set; } = default!;

    private PassengerId() { }
    private PassengerId(string value) => Value = value;

    public static PassengerId Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Passenger id cannot be empty.");

        var normalized = value.Trim();
        if (normalized.Length < 5 || normalized.Length > 20)
            throw new DomainException("Passenger id must be 5-20 characters.");

        return new PassengerId(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
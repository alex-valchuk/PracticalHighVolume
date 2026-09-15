using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class BookingReference : ValueObject
{
    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    private static readonly Random Rng = new();

    public string Value { get; private set; } = default!;

    private BookingReference() { }
    private BookingReference(string value) => Value = value;

    public static BookingReference Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Booking reference cannot be empty.");

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length != 6 || !normalized.All(char.IsLetterOrDigit))
            throw new DomainException("Booking reference must be exactly 6 alphanumeric characters.");

        return new BookingReference(normalized);
    }

    public static BookingReference Generate()
    {
        Span<char> buffer = stackalloc char[6];
        for (int i = 0; i < 6; i++)
            buffer[i] = Alphabet[Rng.Next(Alphabet.Length)];
        return new BookingReference(new string(buffer));
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
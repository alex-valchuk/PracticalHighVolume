using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class Payment : Entity<Guid>
{
    public Guid BookingId { get; private set; }
    public decimal Amount { get; private set; }
    public string Currency { get; private set; } = default!;
    public PaymentStatus Status { get; private set; }
    public string? ExternalReference { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset? RefundedAt { get; private set; }

    private Payment() { }

    private Payment(Guid id, Guid bookingId, decimal amount, string currency, string? externalReference)
        : base(id)
    {
        BookingId = bookingId;
        Amount = amount;
        Currency = currency;
        ExternalReference = externalReference;
        CreatedAt = DateTimeOffset.UtcNow;
    }

    public static Payment CreateCharged(Guid bookingId, decimal amount, string currency, string? externalReference)
    {
        if (bookingId == Guid.Empty) throw new DomainException("BookingId is required.");
        if (amount <= 0) throw new DomainException("Payment amount must be positive.");
        if (string.IsNullOrWhiteSpace(currency)) throw new DomainException("Currency is required.");

        return new Payment(Guid.NewGuid(), bookingId, amount, currency.ToUpperInvariant(), externalReference)
        {
            Status = PaymentStatus.Charged
        };
    }

    public static Payment CreateFailed(Guid bookingId, decimal amount, string currency)
    {
        return new Payment(Guid.NewGuid(), bookingId, amount, currency.ToUpperInvariant(), null)
        {
            Status = PaymentStatus.Failed
        };
    }

    public void MarkRefunded()
    {
        if (Status == PaymentStatus.Refunded) return;
        if (Status != PaymentStatus.Charged)
            throw new DomainException("Only charged payments can be refunded.");

        Status = PaymentStatus.Refunded;
        RefundedAt = DateTimeOffset.UtcNow;
    }
}
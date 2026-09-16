using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.Persistence;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Bookings.Infrastructure.Integration.Payments;

/// <summary>
/// Deterministic fake payment gateway. Behaviour is driven by PaymentOptions.
/// Persists every attempt (charged or failed) to booking.payments so that
/// compensation and audits have durable records.
/// </summary>
internal sealed class FakePaymentGateway : IPaymentGateway
{
    private readonly BookingDbContext _db;
    private readonly PaymentOptions _options;
    private readonly ILogger<FakePaymentGateway> _logger;

    private static readonly Random Rng = new();

    public FakePaymentGateway(
        BookingDbContext db,
        IOptions<PaymentOptions> options,
        ILogger<FakePaymentGateway> logger)
    {
        _db = db;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<PaymentResult> ChargeAsync(
        Guid bookingId, decimal amount, string currency, CancellationToken ct = default)
    {
        var delay = _options.MaxDelayMs > _options.MinDelayMs
            ? Rng.Next(_options.MinDelayMs, _options.MaxDelayMs + 1)
            : Math.Max(0, _options.MinDelayMs);

        if (delay > 0)
            await Task.Delay(delay, ct);

        var failRate = Math.Clamp(_options.FailureRatePercent, 0, 100);
        var shouldFail = Rng.Next(100) < failRate;

        if (shouldFail)
        {
            var failed = Domain.Aggregates.Payment.CreateFailed(bookingId, amount, currency);
            _db.Payments.Add(failed);
            await _db.SaveChangesAsync(ct);

            _logger.LogWarning(
                "FakePaymentGateway DECLINED charge: booking={BookingId} amount={Amount} {Currency}",
                bookingId, amount, currency);

            return new PaymentResult(false, null, "Card declined (fake).");
        }

        var reference = "FAKE-" + Guid.NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant();
        var payment = Domain.Aggregates.Payment.CreateCharged(bookingId, amount, currency, reference);
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "FakePaymentGateway CHARGED: booking={BookingId} amount={Amount} {Currency} payment={PaymentId} ref={Ref}",
            bookingId, amount, currency, payment.Id, reference);

        return new PaymentResult(true, payment.Id, null, _options.SimulateFailureAfterCharge);
    }

    public async Task RefundAsync(Guid paymentId, CancellationToken ct = default)
    {
        var payment = await _db.Payments.FindAsync(new object[] { paymentId }, ct);
        if (payment is null)
        {
            _logger.LogWarning("FakePaymentGateway REFUND skipped - payment {PaymentId} not found", paymentId);
            return;
        }

        payment.MarkRefunded();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("FakePaymentGateway REFUNDED: payment={PaymentId}", paymentId);
    }
}
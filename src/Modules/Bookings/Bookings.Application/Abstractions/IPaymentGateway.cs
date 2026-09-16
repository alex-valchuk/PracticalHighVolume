namespace Bookings.Application.Abstractions;

public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(Guid bookingId, decimal amount, string currency, CancellationToken ct = default);
    Task RefundAsync(Guid paymentId, CancellationToken ct = default);
}

/// <summary>
/// Result of a charge attempt.
/// SimulateFailureAfterCharge is a demo/testing flag: when true, the saga
/// handler treats the charge as successful (paymentId is set) but then
/// throws internally right after it, so that the compensation path
/// (refund + release + expire) can be exercised end-to-end.
/// In production this flag is always false.
/// </summary>
public sealed record PaymentResult(
    bool Success,
    Guid? PaymentId,
    string? FailureReason,
    bool SimulateFailureAfterCharge = false);
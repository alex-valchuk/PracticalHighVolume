namespace Bookings.Infrastructure.Options;

/// <summary>
/// Runtime-mutable simulation flag used by FakePaymentGateway.
/// Lives as a singleton so that a dev endpoint can flip it without restart.
/// Not used in production.
/// </summary>
public sealed class PaymentSimulationState
{
    public bool SimulateFailureAfterCharge { get; set; }
}
namespace Bookings.Infrastructure.Options;

public sealed class PaymentOptions
{
    public const string SectionName = "Payment";

    /// <summary>0-100. Percent of charge attempts that will be declined.</summary>
    public int FailureRatePercent { get; set; } = 20;

    public int MinDelayMs { get; set; } = 100;
    public int MaxDelayMs { get; set; } = 500;

    /// <summary>
    /// Demo/testing hook. When true, the charge succeeds (a Payment row is
    /// written with status Charged) and then the saga handler immediately
    /// throws, triggering compensation (refund + release seats + expire).
    /// Leave false in production.
    /// </summary>
    public bool SimulateFailureAfterCharge { get; set; } = false;
}
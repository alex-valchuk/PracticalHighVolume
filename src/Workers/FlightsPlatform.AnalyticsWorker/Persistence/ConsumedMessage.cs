namespace FlightsPlatform.AnalyticsWorker.Persistence;

public sealed class ConsumedMessage
{
    public Guid MessageId { get; set; }
    public DateTimeOffset ConsumedAt { get; set; }
}
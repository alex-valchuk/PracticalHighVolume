namespace FlightsPlatform.NotificationWorker.Persistence;

public sealed class ConsumedMessage
{
    public Guid MessageId { get; set; }
    public DateTimeOffset ConsumedAt { get; set; }
}
namespace FlightsPlatform.AnalyticsWorker.Persistence;

public sealed class AuditEntry
{
    public Guid Id { get; set; }
    public Guid MessageId { get; set; }
    public string EventType { get; set; } = default!;
    public string Payload { get; set; } = default!;
    public DateTimeOffset RecordedAt { get; set; }
}
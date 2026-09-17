namespace FlightsPlatform.Contracts.Common;

/// <summary>
/// Base type for all integration events published to the broker.
/// Every event carries an EventId for idempotency and a CorrelationId for tracing.
/// </summary>
public abstract record IntegrationEventBase
{
    public Guid EventId { get; init; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; init; } = DateTimeOffset.UtcNow;
    public string? CorrelationId { get; init; }
}
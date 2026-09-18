using System.Text.Json;
using FlightsPlatform.AnalyticsWorker.Persistence;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public abstract class AuditConsumerBase<TEvent> : IConsumer<TEvent>
    where TEvent : class
{
    protected abstract string EventType { get; }

    private readonly AnalyticsDbContext _db;
    private readonly ILogger _logger;

    protected AuditConsumerBase(AnalyticsDbContext db, ILogger logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<TEvent> context)
    {
        var msgId = context.MessageId ?? Guid.NewGuid();

        var alreadyProcessed = await _db.ConsumedMessages
            .AnyAsync(m => m.MessageId == msgId, context.CancellationToken);

        if (alreadyProcessed)
        {
            _logger.LogWarning(
                "[AnalyticsWorker] Duplicate message {MessageId} ({EventType}) - skipped",
                msgId, EventType);
            return;
        }

        var payload = JsonSerializer.Serialize(context.Message, context.Message.GetType());

        _db.AuditEntries.Add(new AuditEntry
        {
            Id = Guid.NewGuid(),
            MessageId = msgId,
            EventType = EventType,
            Payload = payload,
            RecordedAt = DateTimeOffset.UtcNow
        });

        _db.ConsumedMessages.Add(new ConsumedMessage
        {
            MessageId = msgId,
            ConsumedAt = DateTimeOffset.UtcNow
        });

        await _db.SaveChangesAsync(context.CancellationToken);

        _logger.LogInformation(
            "[AnalyticsWorker] Audited {EventType} (message {MessageId})",
            EventType, msgId);
    }
}
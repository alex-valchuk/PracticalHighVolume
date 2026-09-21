using System.Text.Json;
using FlightsPlatform.AnalyticsWorker.Persistence;
using FlightsPlatform.Contracts.Common;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public abstract class AuditConsumerBase<TEvent> : IConsumer<TEvent>
    where TEvent : IntegrationEventBase
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
        var msg = context.Message;
        var messageId = msg.EventId;

        var alreadyProcessed = await _db.ConsumedMessages
            .AnyAsync(m => m.MessageId == messageId, context.CancellationToken);

        if (alreadyProcessed)
        {
            _logger.LogWarning(
                "[AnalyticsWorker] Duplicate message {MessageId} ({EventType}) - skipped",
                messageId, EventType);
            return;
        }

        var payload = JsonSerializer.Serialize(msg, msg.GetType());

        _db.AuditEntries.Add(new AuditEntry
        {
            Id = Guid.NewGuid(),
            MessageId = messageId,
            EventType = EventType,
            Payload = payload,
            RecordedAt = DateTimeOffset.UtcNow
        });

        _db.ConsumedMessages.Add(new ConsumedMessage
        {
            MessageId = messageId,
            ConsumedAt = DateTimeOffset.UtcNow
        });

        await _db.SaveChangesAsync(context.CancellationToken);

        _logger.LogInformation(
            "[AnalyticsWorker] Audited {EventType} (message {MessageId})",
            EventType, messageId);
    }
}
using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.NotificationWorker.Persistence;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.NotificationWorker.Consumers;

public sealed class BookingConfirmedConsumer : IConsumer<BookingConfirmedIntegrationEvent>
{
    private readonly NotificationDbContext _db;
    private readonly ILogger<BookingConfirmedConsumer> _logger;

    public BookingConfirmedConsumer(NotificationDbContext db, ILogger<BookingConfirmedConsumer> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<BookingConfirmedIntegrationEvent> context)
    {
        var msg = context.Message;

        // Idempotency: skip if this message was already processed.
        var alreadyProcessed = await _db.ConsumedMessages
            .AnyAsync(m => m.MessageId == msg.EventId, context.CancellationToken);

        if (alreadyProcessed)
        {
            _logger.LogWarning(
                "[NotificationWorker] Duplicate message {MessageId} ({EventType}) - skipped",
                msg.EventId, nameof(BookingConfirmedIntegrationEvent));
            return;
        }

        // Simulated email send.
        _logger.LogInformation(
            "[EMAIL] To: passenger {PassengerId} ({PassengerName}) | Subject: Booking {Ref} confirmed | Amount: {Amount} {Currency} | Tickets: {Count}",
            msg.PassengerId, msg.PassengerName, msg.BookingReference, msg.TotalAmount, msg.Currency, msg.TicketCount);

        _db.ConsumedMessages.Add(new ConsumedMessage
        {
            MessageId = msg.EventId,
            ConsumedAt = DateTimeOffset.UtcNow
        });
        await _db.SaveChangesAsync(context.CancellationToken);
    }
}
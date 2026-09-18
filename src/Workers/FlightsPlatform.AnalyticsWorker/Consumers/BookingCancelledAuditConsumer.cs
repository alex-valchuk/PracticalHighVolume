using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class BookingCancelledAuditConsumer : AuditConsumerBase<BookingCancelledIntegrationEvent>
{
    protected override string EventType => "BookingCancelled";

    public BookingCancelledAuditConsumer(AnalyticsDbContext db, ILogger<BookingCancelledAuditConsumer> logger) : base(db, logger) { }
}
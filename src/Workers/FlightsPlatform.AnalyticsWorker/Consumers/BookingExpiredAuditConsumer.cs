using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class BookingExpiredAuditConsumer : AuditConsumerBase<BookingExpiredIntegrationEvent>
{
    protected override string EventType => "BookingExpired";

    public BookingExpiredAuditConsumer(AnalyticsDbContext db, ILogger<BookingExpiredAuditConsumer> logger) : base(db, logger) { }
}
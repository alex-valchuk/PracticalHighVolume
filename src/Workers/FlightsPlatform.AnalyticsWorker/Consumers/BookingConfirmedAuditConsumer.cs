using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class BookingConfirmedAuditConsumer : AuditConsumerBase<BookingConfirmedIntegrationEvent>
{
    protected override string EventType => "BookingConfirmed";

    public BookingConfirmedAuditConsumer(AnalyticsDbContext db, ILogger<BookingConfirmedAuditConsumer> logger) : base(db, logger) { }
}
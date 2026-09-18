using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class BookingCreatedAuditConsumer : AuditConsumerBase<BookingCreatedIntegrationEvent>
{
    protected override string EventType => "BookingCreated";

    public BookingCreatedAuditConsumer(AnalyticsDbContext db, ILogger<BookingCreatedAuditConsumer> logger) : base(db, logger) { }
}
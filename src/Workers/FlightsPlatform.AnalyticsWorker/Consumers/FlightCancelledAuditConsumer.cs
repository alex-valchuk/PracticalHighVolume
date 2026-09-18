using FlightsPlatform.Contracts.FlightCatalog;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class FlightCancelledAuditConsumer : AuditConsumerBase<FlightCancelledIntegrationEvent>
{
    protected override string EventType => "FlightCancelled";

    public FlightCancelledAuditConsumer(AnalyticsDbContext db, ILogger<FlightCancelledAuditConsumer> logger) : base(db, logger) { }
}
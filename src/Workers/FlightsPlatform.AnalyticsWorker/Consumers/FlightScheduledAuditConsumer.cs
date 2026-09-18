using FlightsPlatform.Contracts.FlightCatalog;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class FlightScheduledAuditConsumer : AuditConsumerBase<FlightScheduledIntegrationEvent>
{
    protected override string EventType => "FlightScheduled";

    public FlightScheduledAuditConsumer(AnalyticsDbContext db, ILogger<FlightScheduledAuditConsumer> logger) : base(db, logger) { }
}
using FlightsPlatform.Contracts.FlightCatalog;
using FlightsPlatform.AnalyticsWorker.Persistence;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.AnalyticsWorker.Consumers;

public sealed class FlightDelayedAuditConsumer : AuditConsumerBase<FlightDelayedIntegrationEvent>
{
    protected override string EventType => "FlightDelayed";

    public FlightDelayedAuditConsumer(AnalyticsDbContext db, ILogger<FlightDelayedAuditConsumer> logger) : base(db, logger) { }
}
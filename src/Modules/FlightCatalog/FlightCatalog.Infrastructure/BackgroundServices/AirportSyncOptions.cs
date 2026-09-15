namespace FlightCatalog.Infrastructure.BackgroundServices;

public sealed class AirportSyncOptions
{
    public const string SectionName = "AirportSync";

    public bool Enabled { get; set; } = true;
    public int IntervalMinutes { get; set; } = 15;
    public bool SyncOnStartup { get; set; } = true;
}
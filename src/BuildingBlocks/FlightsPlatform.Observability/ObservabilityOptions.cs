namespace FlightsPlatform.Observability;

public sealed class ObservabilityOptions
{
    public const string SectionName = "Observability";

    public string ServiceName { get; set; } = "FlightsPlatform";
    public string OtlpEndpoint { get; set; } = "http://localhost:4317";
    public double TraceSamplingRatio { get; set; } = 1.0;
    public bool EnableConsoleExporter { get; set; } = false;
    public int MetricsPort { get; set; } = 9100;
}
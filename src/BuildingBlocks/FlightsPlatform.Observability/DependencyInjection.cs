using MassTransit.Logging;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace FlightsPlatform.Observability;

public enum PrometheusExporterMode
{
    None,
    AspNetCore,
    HttpListener
}

public static class DependencyInjection
{
    public static IServiceCollection AddFlightsPlatformObservability(
        this IServiceCollection services,
        IConfiguration configuration,
        Action<ObservabilityOptions>? configure = null,
        PrometheusExporterMode prometheusMode = PrometheusExporterMode.None)
    {
        var options = new ObservabilityOptions();
        configuration.GetSection(ObservabilityOptions.SectionName).Bind(options);
        configure?.Invoke(options);

        services.Configure<ObservabilityOptions>(o =>
        {
            o.ServiceName = options.ServiceName;
            o.OtlpEndpoint = options.OtlpEndpoint;
            o.TraceSamplingRatio = options.TraceSamplingRatio;
            o.EnableConsoleExporter = options.EnableConsoleExporter;
            o.MetricsPort = options.MetricsPort;
        });

        services.AddOpenTelemetry()
            .ConfigureResource(r => r
                .AddService(options.ServiceName)
                .AddAttributes(new Dictionary<string, object>
                {
                    ["deployment.environment"] =
                        Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? "Development"
                }))
            .WithTracing(tracing =>
            {
                tracing
                    .SetSampler(new ParentBasedSampler(
                        new TraceIdRatioBasedSampler(options.TraceSamplingRatio)))
                    .AddSource(ActivitySources.All().ToArray())
                    .AddSource(DiagnosticHeaders.DefaultListenerName)
                    .AddAspNetCoreInstrumentation(o =>
                    {
                        o.RecordException = true;
                        o.Filter = ctx =>
                            !ctx.Request.Path.StartsWithSegments("/metrics") &&
                            !ctx.Request.Path.StartsWithSegments("/health");
                    })
                    .AddHttpClientInstrumentation()
                    .AddEntityFrameworkCoreInstrumentation(o =>
                    {
                        o.SetDbStatementForText = false;
                    })
                    .AddOtlpExporter(o => o.Endpoint = new Uri(options.OtlpEndpoint));
            })
            .WithMetrics(metrics =>
            {
                metrics
                    .AddMeter(Meters.Name)
                    .AddMeter("MassTransit")
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation()
                    .AddOtlpExporter(o => o.Endpoint = new Uri(options.OtlpEndpoint));

                if (prometheusMode == PrometheusExporterMode.AspNetCore)
                {
                    metrics.AddPrometheusExporter();
                }
                else if (prometheusMode == PrometheusExporterMode.HttpListener)
                {
                    metrics.AddPrometheusHttpListener(o =>
                    {
                        o.UriPrefixes = new[] { "http://*:" + options.MetricsPort + "/" };
                    });
                }
            });

        return services;
    }
}
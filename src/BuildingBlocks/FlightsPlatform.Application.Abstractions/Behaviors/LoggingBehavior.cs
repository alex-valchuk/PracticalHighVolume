using System.Diagnostics;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.Application.Abstractions.Behaviors;

/// <summary>
/// Single cross-module logging behavior. Registered once in the host.
/// Module name is derived from the request namespace, so no module registers
/// its own copy - avoids double-handling and cross-module leakage.
/// </summary>
public sealed class LoggingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<LoggingBehavior<TRequest, TResponse>> _logger;

    public LoggingBehavior(ILogger<LoggingBehavior<TRequest, TResponse>> logger)
        => _logger = logger;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var name = typeof(TRequest).Name;
        var module = ResolveModule(typeof(TRequest));
        var sw = Stopwatch.StartNew();

        _logger.LogInformation("[{Module}] Handling {RequestName}", module, name);

        try
        {
            var response = await next();
            sw.Stop();
            _logger.LogInformation("[{Module}] Handled {RequestName} in {Elapsed} ms",
                module, name, sw.ElapsedMilliseconds);
            return response;
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex, "[{Module}] Error handling {RequestName} after {Elapsed} ms",
                module, name, sw.ElapsedMilliseconds);
            throw;
        }
    }

    private static string ResolveModule(Type requestType)
    {
        var ns = requestType.Namespace ?? string.Empty;
        if (ns.StartsWith("FlightCatalog")) return "FlightCatalog";
        if (ns.StartsWith("Bookings")) return "Bookings";
        return "Shared";
    }
}
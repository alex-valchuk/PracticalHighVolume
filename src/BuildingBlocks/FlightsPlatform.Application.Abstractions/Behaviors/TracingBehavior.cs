using System.Diagnostics;
using FlightsPlatform.Observability;
using MediatR;

namespace FlightsPlatform.Application.Abstractions.Behaviors;

/// <summary>
/// Creates one span per MediatR command/query.
/// Span name: "command.execute {RequestName}" or "query.execute {RequestName}".
/// Tags: request.name, request.module (derived from namespace).
/// </summary>
public sealed class TracingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var requestName = typeof(TRequest).Name;
        var isQuery = requestName.EndsWith("Query", StringComparison.Ordinal);
        var operation = isQuery ? "query.execute" : "command.execute";
        var module = ResolveModule(typeof(TRequest));

        using var activity = ActivitySources.Commands.Instance.StartActivity(
            $"{operation} {requestName}",
            ActivityKind.Internal);

        activity?.SetTag("request.name", requestName);
        activity?.SetTag("request.module", module);
        activity?.SetTag("request.kind", isQuery ? "query" : "command");

        try
        {
            var response = await next();
            activity?.SetStatus(ActivityStatusCode.Ok);
            return response;
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.AddException(ex);
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
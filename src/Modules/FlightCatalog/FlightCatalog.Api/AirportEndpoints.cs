using FlightCatalog.Application.Commands.SyncAirports;
using FlightCatalog.Application.Queries.GetAirportByCode;
using FlightCatalog.Application.Queries.GetAllAirports;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace FlightCatalog.Api;

public static class AirportEndpoints
{
    public static IEndpointRouteBuilder MapAirportEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/flight-catalog/airports").WithTags("Flight Catalog - Airports");

        group.MapGet("/{code}", async (
            string code,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetAirportByCodeQuery(code), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapGet("/", async (
            int? page,
            int? pageSize,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(
                new GetAllAirportsQuery(page ?? 1, pageSize ?? 100), ct);
            return Results.Ok(new
            {
                items = result.Items,
                total = result.Total,
                page = page ?? 1,
                pageSize = pageSize ?? 100
            });
        });

        group.MapPost("/sync", async (
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new SyncAirportsCommand(), ct);
            return result.IsSuccess
                ? Results.Ok(new
                {
                    read = result.Value!.Read,
                    created = result.Value.Created,
                    updated = result.Value.Updated,
                    skipped = result.Value.Skipped
                })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        return app;
    }
}
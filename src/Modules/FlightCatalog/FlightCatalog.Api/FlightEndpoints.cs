using FlightCatalog.Api.Contracts;
using FlightCatalog.Application.Commands.CancelFlight;
using FlightCatalog.Application.Commands.DelayFlight;
using FlightCatalog.Application.Commands.ScheduleFlight;
using FlightCatalog.Application.Queries.GetFlightById;
using FlightCatalog.Application.Queries.SearchFlights;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace FlightCatalog.Api;

public static class FlightEndpoints
{
    public static IEndpointRouteBuilder MapFlightCatalogEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/flight-catalog/flights").WithTags("Flight Catalog");

        group.MapPost("/", async (
            ScheduleFlightRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new ScheduleFlightCommand(
                req.FlightNumber, req.DepartureAirport, req.ArrivalAirport,
                req.Departure, req.Arrival, req.AircraftModel);

            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/flight-catalog/flights/{result.Value}",
                    new { id = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/delay", async (
            Guid id,
            DelayFlightRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new DelayFlightCommand(id, req.NewDeparture, req.NewArrival), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/cancel", async (
            Guid id,
            CancelFlightRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new CancelFlightCommand(id, req.Reason), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapGet("/{id:guid}", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetFlightByIdQuery(id), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapGet("/", async (
            string from,
            string to,
            DateOnly date,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var rows = await mediator.Send(new SearchFlightsQuery(from, to, date), ct);
            return Results.Ok(rows);
        });

        return app;
    }
}
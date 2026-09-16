using Bookings.Api.Contracts;
using Bookings.Application.Commands.AddTicket;
using Bookings.Application.Commands.CancelBooking;
using Bookings.Application.Commands.ConfirmBooking;
using Bookings.Application.Commands.CreateBooking;
using Bookings.Application.Queries.GetBookingById;
using Bookings.Application.Queries.GetBookingsList;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace Bookings.Api;

public static class BookingsEndpoints
{
    public static IEndpointRouteBuilder MapBookingsEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/bookings").WithTags("Bookings");

        group.MapPost("/", async (
            CreateBookingRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new CreateBookingCommand(req.PassengerId, req.PassengerName, req.Currency);
            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/bookings/{result.Value}", new { id = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapGet("/", async (
            int? page,
            int? pageSize,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(
                new GetBookingsListQuery(page ?? 1, pageSize ?? 100), ct);
            return Results.Ok(new
            {
                items = result.Items,
                total = result.Total,
                page = page ?? 1,
                pageSize = pageSize ?? 100
            });
        });

        group.MapGet("/{id:guid}", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetBookingByIdQuery(id), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapPost("/{id:guid}/tickets", async (
            Guid id,
            AddTicketRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new AddTicketCommand(
                id, req.FlightId, req.PassengerId, req.PassengerName, req.Amount);

            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/bookings/{id}/tickets/{result.Value}",
                    new { ticketId = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/confirm", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new ConfirmBookingCommand(id), ct);
            return result.IsSuccess
                ? Results.Ok(result.Value)
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/cancel", async (
            Guid id,
            CancelBookingRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new CancelBookingCommand(id, req.Reason), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        return app;
    }
}
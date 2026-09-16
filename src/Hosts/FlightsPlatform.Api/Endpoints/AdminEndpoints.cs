using Bookings.Infrastructure.Options;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace FlightsPlatform.Api.Endpoints;

public static class AdminEndpoints
{
    public static IEndpointRouteBuilder MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/admin").WithTags("Admin (dev only)");

        group.MapGet("/payment/simulate-failure", (PaymentSimulationState state) =>
            Results.Ok(new { enabled = state.SimulateFailureAfterCharge }));

        group.MapPost("/payment/simulate-failure", (
            SimulateFailureRequest body,
            PaymentSimulationState state) =>
        {
            state.SimulateFailureAfterCharge = body.Enabled;
            return Results.Ok(new { enabled = state.SimulateFailureAfterCharge });
        });

        return app;
    }

    public sealed record SimulateFailureRequest(bool Enabled);
}
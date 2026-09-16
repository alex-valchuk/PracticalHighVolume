using Bookings.Domain;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;

namespace FlightsPlatform.Api.Endpoints;

public static class DashboardEndpoints
{
    public static IEndpointRouteBuilder MapDashboardEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/dashboard/summary", async (
            FlightCatalogDbContext fcDb,
            BookingDbContext bkDb,
            CancellationToken ct) =>
        {
            var flights = await fcDb.Flights.CountAsync(ct);
            var airports = await fcDb.Airports.CountAsync(ct);
            var bookings = await bkDb.Bookings.CountAsync(ct);
            var activeBookings = await bkDb.Bookings
                .CountAsync(b => b.Status == BookingStatus.Pending, ct);

            return Results.Ok(new
            {
                flights,
                airports,
                bookings,
                activeBookings
            });
        })
        .WithTags("Dashboard")
        .WithName("GetDashboardSummary");

        return app;
    }
}
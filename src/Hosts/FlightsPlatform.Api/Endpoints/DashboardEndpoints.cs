using Bookings.Domain;
using Bookings.Infrastructure.Persistence;
using FlightsPlatform.Api.External;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FlightsPlatform.Api.Endpoints;

public static class DashboardEndpoints
{
    public static IEndpointRouteBuilder MapDashboardEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/dashboard/summary", async (
            FlightCatalogDashboardClient flightCatalog,
            BookingDbContext bkDb,
            ILoggerFactory loggerFactory,
            CancellationToken ct) =>
        {
            var logger = loggerFactory.CreateLogger("DashboardEndpoints");

            DashboardCounters counters;
            try
            {
                counters = await flightCatalog.GetCountersAsync(ct);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to fetch counters from FlightCatalog.Service. BaseAddress={BaseAddress}",
                    flightCatalog.HttpBaseAddress);
                return Results.Problem(
                    title: "FlightCatalog unavailable",
                    detail: ex.GetType().Name + ": " + ex.Message,
                    statusCode: 503);
            }

            var bookings = await bkDb.Bookings.CountAsync(ct);
            var activeBookings = await bkDb.Bookings
                .CountAsync(b => b.Status == BookingStatus.Pending, ct);

            return Results.Ok(new
            {
                flights = counters.Flights,
                airports = counters.Airports,
                bookings,
                activeBookings
            });
        })
        .WithTags("Dashboard")
        .WithName("GetDashboardSummary");

        return app;
    }
}
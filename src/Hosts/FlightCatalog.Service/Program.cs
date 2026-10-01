using Scalar.AspNetCore;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Application.Abstractions.Behaviors;
using FlightsPlatform.FlightCatalog.Service.Messaging;
using FlightsPlatform.Infrastructure.Redis;
using FlightCatalog.Api;
using MassTransit;
using MediatR;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssemblies(
        typeof(FlightCatalog.Application.DependencyInjection).Assembly);

    cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
    cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
    cfg.AddOpenBehavior(typeof(TracingBehavior<,>));
});

builder.Services.AddRedisInfrastructure(builder.Configuration);

builder.Services.AddMassTransit(x =>
{
    x.SetKebabCaseEndpointNameFormatter();

    x.UsingRabbitMq((context, cfg) =>
    {
        var host = builder.Configuration["RabbitMq:Host"] ?? "localhost";
        var port = builder.Configuration.GetValue<int?>("RabbitMq:Port") ?? 5672;
        var vhost = builder.Configuration["RabbitMq:VirtualHost"] ?? "/";
        var user = builder.Configuration["RabbitMq:Username"] ?? "guest";
        var pass = builder.Configuration["RabbitMq:Password"] ?? "guest";

        var vhostInUri = vhost.TrimStart('/');
        var rabbitUri = new Uri($"rabbitmq://{host}:{port}/{vhostInUri}");

        cfg.Host(rabbitUri, h =>
        {
            h.Username(user);
            h.Password(pass);
        });

        cfg.ConfigureEndpoints(context);
    });
});

builder.Services.AddScoped<IIntegrationEventPublisher, MassTransitEventPublisher>();

builder.Services.AddFlightCatalogApplication();
builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.MapAirportEndpoints();
app.MapFlightCatalogEndpoints();

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "flight-catalog" }));

app.MapGet("/internal/dashboard/counters", async (
    FlightCatalogDbContext db,
    CancellationToken ct) =>
{
    var flights = await db.Flights.CountAsync(ct);
    var airports = await db.Airports.CountAsync(ct);
    return Results.Ok(new { flights, airports });
});

using (var scope = app.Services.CreateScope())
{
    var fcDb = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await fcDb.Database.MigrateAsync();
}


// Phase 9: airport sync requires the external demo database, which is not
// provisioned in every environment (notably, Aspire). Return a clear 503
// instead of letting the underlying Npgsql error bubble up as 500.
var syncEnabled = builder.Configuration.GetValue<bool?>("AirportSync:Enabled") ?? true;
if (!syncEnabled)
{
    app.Use(async (ctx, next) =>
    {
        if (HttpMethods.IsPost(ctx.Request.Method) &&
            ctx.Request.Path.StartsWithSegments("/flight-catalog/airports/sync"))
        {
            ctx.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            await ctx.Response.WriteAsJsonAsync(new
            {
                error = "sync_disabled",
                message = "Airport sync requires the external demo database, which is not provisioned in this environment. Use the Local (docker-compose) or Kubernetes environment instead."
            });
            return;
        }
        await next();
    });

    app.MapGet("/flight-catalog/airports/sync/status", () => Results.Ok(new
    {
        enabled = false,
        reason = "AirportSync:Enabled is false in this environment."
    }));
}
else
{
    app.MapGet("/flight-catalog/airports/sync/status", () => Results.Ok(new
    {
        enabled = true
    }));
}
app.Run();
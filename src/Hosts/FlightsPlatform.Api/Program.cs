using Bookings.Api;
using Bookings.Application;
using Bookings.Infrastructure;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FlightsPlatform.Api.Endpoints;
using FlightsPlatform.Api.Messaging;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Application.Abstractions.Behaviors;
using FlightsPlatform.Infrastructure.Redis;
using FluentValidation;
using MassTransit;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;
using Serilog;
using FlightsPlatform.SharedKernel;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File(
        path: "logs/api-.log",
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 7,
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj}{NewLine}{Exception}")
    .CreateLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseSerilog();

    builder.Services.AddControllers();
    builder.Services.AddOpenApi();

    builder.Services.AddCors(options =>
    {
        options.AddPolicy("frontend", policy =>
        {
            policy.WithOrigins("http://localhost:4200")
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        });
    });

    builder.Services.AddMediatR(cfg =>
    {
        cfg.RegisterServicesFromAssemblies(
            typeof(FlightCatalog.Application.DependencyInjection).Assembly,
            typeof(Bookings.Application.DependencyInjection).Assembly);

        cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
        cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
    });

    builder.Services.AddRedisInfrastructure(builder.Configuration);

    builder.Services.AddFlightCatalogApplication();
    builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

    builder.Services.AddBookingsApplication();
    builder.Services.AddBookingsInfrastructure(builder.Configuration);

    builder.Services.AddScoped<IIntegrationEventPublisher, MassTransitEventPublisher>();

    builder.Services.AddMassTransit(x =>
    {
        x.SetKebabCaseEndpointNameFormatter();

        // Register outbox for each DbContext.
        // Disable lock-statement schema caching (second arg = false) because
        // MassTransit 9.2 caches the lock SQL by entity type; with two contexts
        // that can reuse the wrong schema. See MassTransit docs on multi-DbContext outbox.
        x.AddEntityFrameworkOutbox<FlightCatalogDbContext>(o =>
        {
            o.UsePostgres(false);
            o.UseBusOutbox();
        });

        x.AddEntityFrameworkOutbox<BookingDbContext>(o =>
        {
            o.UsePostgres(false);
            o.UseBusOutbox();
        });

        // Choose the default bus outbox for non-typed IPublishEndpoint usage.
        // Must be called on the registration configurator (x), NOT inside AddEntityFrameworkOutbox.
        // For Phase 6.1 we route all Publish() calls through flight_catalog.outbox.
        // Phase 6.2 will move to per-module typed publishers.
        x.UseDefaultEntityFrameworkBusOutbox<FlightCatalogDbContext>();

        x.UsingRabbitMq((context, cfg) =>
        {
            var host = builder.Configuration["RabbitMq:Host"] ?? "localhost";
            var vhost = builder.Configuration["RabbitMq:VirtualHost"] ?? "/";
            var user = builder.Configuration["RabbitMq:Username"] ?? "flights";
            var pass = builder.Configuration["RabbitMq:Password"] ?? "flights_dev_password";

            cfg.Host(host, vhost, h =>
            {
                h.Username(user);
                h.Password(pass);
            });

            cfg.ConfigureEndpoints(context);
        });
    });

    var app = builder.Build();

    if (app.Environment.IsDevelopment())
    {
        app.MapOpenApi();
        app.MapScalarApiReference();
        app.UseCors("frontend");
    }

    app.UseExceptionHandler(errApp => errApp.Run(async ctx =>
    {
        var feature = ctx.Features.Get<IExceptionHandlerFeature>();
        var ex = feature?.Error;

        var (status, payload) = ex switch
        {
            ValidationException ve => (StatusCodes.Status400BadRequest,
                (object)new
                {
                    error = "validation_failed",
                    details = ve.Errors.Select(e => e.ErrorMessage)
                }),
            DomainException de => (StatusCodes.Status400BadRequest,
                new { error = "domain_error", message = de.Message }),
            _ => (StatusCodes.Status500InternalServerError,
                new { error = "internal_error" })
        };

        ctx.Response.StatusCode = status;
        await ctx.Response.WriteAsJsonAsync(payload);
    }));

    app.UseSerilogRequestLogging();

    app.UseHttpsRedirection();
    app.MapControllers();
    app.MapFlightCatalogEndpoints();
    app.MapAirportEndpoints();
    app.MapBookingsEndpoints();
    app.MapDashboardEndpoints();

    if (app.Environment.IsDevelopment())
    {
        app.MapAdminEndpoints();
    }

    app.MapGet("/health", () => Results.Ok(new
    {
        status = "ok",
        time = DateTimeOffset.UtcNow
    }))
    .WithTags("Health")
    .WithName("GetHealth");

    using (var scope = app.Services.CreateScope())
    {
        var fcDb = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
        await fcDb.Database.MigrateAsync();

        var bkDb = scope.ServiceProvider.GetRequiredService<BookingDbContext>();
        await bkDb.Database.MigrateAsync();
    }

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "API terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}
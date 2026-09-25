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
using FlightsPlatform.Observability;
using FluentValidation;
using MassTransit;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using OpenTelemetry.Metrics;
using Scalar.AspNetCore;
using Serilog;
using FlightsPlatform.SharedKernel;

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .WriteTo.Console(
        outputTemplate:
        "[{Timestamp:HH:mm:ss} {Level:u3}] [trace={TraceId} span={SpanId}] {Message:lj}{NewLine}{Exception}")
    .WriteTo.File(
        path: "logs/api-.log",
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 7,
        outputTemplate:
        "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [trace={TraceId} span={SpanId}] {Message:lj}{NewLine}{Exception}")
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

    builder.Services.AddFlightsPlatformObservability(
        builder.Configuration,
        o => o.ServiceName = "FlightsPlatform.Api",
        PrometheusExporterMode.AspNetCore);

    builder.Services.AddHealthChecks()
        .AddNpgSql(
            builder.Configuration.GetConnectionString("FlightCatalog")!,
            name: "postgres",
            tags: new[] { "ready" })
        .AddRedis(
            builder.Configuration["Redis:ConnectionString"] ?? "127.0.0.1:6379",
            name: "redis",
            tags: new[] { "ready" });

    builder.Services.AddMediatR(cfg =>
    {
        cfg.RegisterServicesFromAssemblies(
            typeof(FlightCatalog.Application.DependencyInjection).Assembly,
            typeof(Bookings.Application.DependencyInjection).Assembly);

        cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
        cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        cfg.AddOpenBehavior(typeof(TracingBehavior<,>));
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

        x.AddEntityFrameworkOutbox<BookingDbContext>(o =>
        {
            o.UsePostgres();
            o.UseBusOutbox();
        });

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

    app.MapHealthChecks("/health/live", new HealthCheckOptions
    {
        Predicate = _ => false
    });

    app.MapHealthChecks("/health/ready", new HealthCheckOptions
    {
        Predicate = check => check.Tags.Contains("ready")
    });

    // OTel Prometheus scraping endpoint (exposes all meters: HTTP, runtime, business).
    app.MapPrometheusScrapingEndpoint();

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
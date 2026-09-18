using FlightsPlatform.AnalyticsWorker.Consumers;
using FlightsPlatform.AnalyticsWorker.Persistence;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

const string DefaultAnalyticsConnection =
    "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

var builder = Host.CreateApplicationBuilder(args);

builder.Configuration
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: false)
    .AddEnvironmentVariables();

builder.Services.AddDbContext<AnalyticsDbContext>(opts =>
{
    var cs = builder.Configuration.GetConnectionString("Analytics");
    if (string.IsNullOrWhiteSpace(cs))
    {
        cs = DefaultAnalyticsConnection;
    }

    opts.UseNpgsql(cs, npgsql =>
        npgsql.MigrationsHistoryTable("__EFMigrationsHistory", AnalyticsDbContext.SchemaName));
});

builder.Services.AddMassTransit(x =>
{
    x.SetKebabCaseEndpointNameFormatter();

    x.AddConsumer<BookingCreatedAuditConsumer>();
    x.AddConsumer<BookingConfirmedAuditConsumer>();
    x.AddConsumer<BookingCancelledAuditConsumer>();
    x.AddConsumer<BookingExpiredAuditConsumer>();
    x.AddConsumer<FlightScheduledAuditConsumer>();
    x.AddConsumer<FlightDelayedAuditConsumer>();
    x.AddConsumer<FlightCancelledAuditConsumer>();

    x.UsingRabbitMq((context, cfg) =>
    {
        var host = builder.Configuration["RabbitMq:Host"] ?? "localhost";
        var vhost = builder.Configuration["RabbitMq:VirtualHost"] ?? "/";
        var user = builder.Configuration["RabbitMq:Username"] ?? "guest";
        var pass = builder.Configuration["RabbitMq:Password"] ?? "guest";

        cfg.Host(host, vhost, h =>
        {
            h.Username(user);
            h.Password(pass);
        });

        cfg.ConfigureEndpoints(context);
    });
});

var host = builder.Build();

using (var scope = host.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AnalyticsDbContext>();
    await db.Database.MigrateAsync();
}

await host.RunAsync();
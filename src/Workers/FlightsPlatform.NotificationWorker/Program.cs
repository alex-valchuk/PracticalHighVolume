using FlightsPlatform.NotificationWorker.Consumers;
using FlightsPlatform.NotificationWorker.Persistence;
using FlightsPlatform.Observability;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Prometheus;

const string DefaultNotificationConnection =
    "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

var builder = Host.CreateApplicationBuilder(args);

builder.Configuration
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: false)
    .AddEnvironmentVariables();

builder.Services.AddFlightsPlatformObservability(
    builder.Configuration,
    o => o.ServiceName = "FlightsPlatform.NotificationWorker");

builder.Services.AddDbContext<NotificationDbContext>(opts =>
{
    var cs = builder.Configuration.GetConnectionString("Notification");
    if (string.IsNullOrWhiteSpace(cs)) cs = DefaultNotificationConnection;

    opts.UseNpgsql(cs, npgsql =>
        npgsql.MigrationsHistoryTable("__EFMigrationsHistory", NotificationDbContext.SchemaName));
});

builder.Services.AddMassTransit(x =>
{
    x.SetKebabCaseEndpointNameFormatter();
    x.AddConsumer<BookingConfirmedConsumer>();

    x.UsingRabbitMq((context, cfg) =>
    {
        var host = builder.Configuration["RabbitMq:Host"] ?? "localhost";
        var vhost = builder.Configuration["RabbitMq:VirtualHost"] ?? "/";
        var user = builder.Configuration["RabbitMq:Username"] ?? "guest";
        var pass = builder.Configuration["RabbitMq:Password"] ?? "guest";

        cfg.Host(host, vhost, h => { h.Username(user); h.Password(pass); });

        cfg.ReceiveEndpoint("notification-booking-confirmed", e =>
        {
            e.UseMessageRetry(r => r.Interval(3, TimeSpan.FromSeconds(2)));
            e.UseDelayedRedelivery(r => r.Intervals(
                TimeSpan.FromSeconds(10),
                TimeSpan.FromSeconds(30),
                TimeSpan.FromMinutes(2)));
            e.ConfigureConsumer<BookingConfirmedConsumer>(context);
        });
    });
});

var host = builder.Build();

var metricsPort = builder.Configuration.GetValue<int?>("Observability:MetricsPort") ?? 9101;
var metricServer = new KestrelMetricServer(port: metricsPort);
metricServer.Start();

using (var scope = host.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<NotificationDbContext>();
    await db.Database.MigrateAsync();
}

await host.RunAsync();
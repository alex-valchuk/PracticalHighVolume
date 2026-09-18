using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FlightsPlatform.NotificationWorker.Persistence;

internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<NotificationDbContext>
{
    public NotificationDbContext CreateDbContext(string[] args)
    {
        var cs = Environment.GetEnvironmentVariable("NOTIFICATION_CONNECTION")
            ?? "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

        var options = new DbContextOptionsBuilder<NotificationDbContext>()
            .UseNpgsql(cs, npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "notification"))
            .Options;

        return new NotificationDbContext(options);
    }
}
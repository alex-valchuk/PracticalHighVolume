using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FlightsPlatform.AnalyticsWorker.Persistence;

internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AnalyticsDbContext>
{
    public AnalyticsDbContext CreateDbContext(string[] args)
    {
        var cs = Environment.GetEnvironmentVariable("ANALYTICS_CONNECTION")
            ?? "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

        var options = new DbContextOptionsBuilder<AnalyticsDbContext>()
            .UseNpgsql(cs, npgsql => npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "analytics"))
            .Options;

        return new AnalyticsDbContext(options);
    }
}
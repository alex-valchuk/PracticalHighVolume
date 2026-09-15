using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FlightCatalog.Infrastructure.Persistence;

/// <summary>
/// Used ONLY by `dotnet ef` at design time (migration generation).
/// Not used at runtime вЂ” the host builds DbContext through DI.
/// </summary>
internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<FlightCatalogDbContext>
{
    public FlightCatalogDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("FLIGHTS_CATALOG_CONNECTION")
            ?? "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

        var optionsBuilder = new DbContextOptionsBuilder<FlightCatalogDbContext>();
        optionsBuilder.UseNpgsql(connectionString);

        return new FlightCatalogDbContext(optionsBuilder.Options);
    }
}
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace FlightCatalog.Infrastructure.Persistence;

public sealed class FlightCatalogDbContext : DbContext
{
    public const string SchemaName = "flight_catalog";

    public FlightCatalogDbContext(DbContextOptions<FlightCatalogDbContext> options)
        : base(options) { }

    public DbSet<Flight> Flights => Set<Flight>();
    public DbSet<Airport> Airports => Set<Airport>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(SchemaName);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FlightCatalogDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
using FlightCatalog.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FlightCatalog.Infrastructure.Persistence.Configurations;

public sealed class FlightConfiguration : IEntityTypeConfiguration<Flight>
{
    public void Configure(EntityTypeBuilder<Flight> builder)
    {
        builder.ToTable("flights");
        builder.HasKey(f => f.Id);
        builder.Property(f => f.Id).HasColumnName("id");

        builder.Property(f => f.Status)
            .HasColumnName("status")
            .HasConversion<int>()
            .IsRequired();

        builder.Property(f => f.AircraftModel)
            .HasColumnName("aircraft_model")
            .HasMaxLength(100)
            .IsRequired();

        builder.ComplexProperty(f => f.FlightNumber, b =>
        {
            b.Property(x => x.Value).HasColumnName("flight_no").HasMaxLength(10).IsRequired();
        });

        builder.ComplexProperty(f => f.Route, route =>
        {
            route.ComplexProperty(r => r.Departure, dep =>
            {
                dep.Property(x => x.Value).HasColumnName("departure_airport").HasMaxLength(3).IsRequired();
            });
            route.ComplexProperty(r => r.Arrival, arr =>
            {
                arr.Property(x => x.Value).HasColumnName("arrival_airport").HasMaxLength(3).IsRequired();
            });
        });

        builder.ComplexProperty(f => f.Schedule, sched =>
        {
            sched.Property(x => x.Departure).HasColumnName("scheduled_departure").IsRequired();
            sched.Property(x => x.Arrival).HasColumnName("scheduled_arrival").IsRequired();
        });

        builder.HasIndex(f => new { f.Status });
    }
}
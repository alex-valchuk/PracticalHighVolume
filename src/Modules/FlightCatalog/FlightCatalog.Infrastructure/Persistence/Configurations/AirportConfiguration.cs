using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FlightCatalog.Infrastructure.Persistence.Configurations;

public sealed class AirportConfiguration : IEntityTypeConfiguration<Airport>
{
    public void Configure(EntityTypeBuilder<Airport> builder)
    {
        builder.ToTable("airports");
        builder.HasKey(a => a.Id);
        builder.Property(a => a.Id).HasColumnName("id");

        builder.Property(a => a.Name).HasColumnName("name").HasMaxLength(200).IsRequired();
        builder.Property(a => a.City).HasColumnName("city").HasMaxLength(200).IsRequired();
        builder.Property(a => a.Timezone).HasColumnName("timezone").HasMaxLength(100).IsRequired();

        // Value converter: EF Core sees this as a plain string column.
        builder.Property(a => a.Code)
            .HasConversion(
                code => code.Value,
                value => AirportCode.Create(value))
            .HasColumnName("airport_code")
            .HasMaxLength(3)
            .IsRequired();

        builder.ComplexProperty(a => a.Coordinates, coords =>
        {
            coords.Property(c => c.Latitude).HasColumnName("latitude").IsRequired();
            coords.Property(c => c.Longitude).HasColumnName("longitude").IsRequired();
        });

        builder.HasIndex(a => a.Code).IsUnique();
    }
}
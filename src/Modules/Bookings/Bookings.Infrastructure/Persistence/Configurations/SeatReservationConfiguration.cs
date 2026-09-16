using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Bookings.Infrastructure.Persistence.Configurations;

public sealed class SeatReservationConfiguration : IEntityTypeConfiguration<SeatReservation>
{
    public void Configure(EntityTypeBuilder<SeatReservation> builder)
    {
        builder.ToTable("seat_reservations");
        builder.HasKey(r => r.Id);
        builder.Property(r => r.Id).HasColumnName("id").ValueGeneratedNever();

        builder.Property(r => r.BookingId).HasColumnName("booking_id").IsRequired();
        builder.Property(r => r.TicketId).HasColumnName("ticket_id").IsRequired();
        builder.Property(r => r.FlightId).HasColumnName("flight_id").IsRequired();
        builder.Property(r => r.Status).HasColumnName("status").HasConversion<int>().IsRequired();
        builder.Property(r => r.ReservedAt).HasColumnName("reserved_at").IsRequired();
        builder.Property(r => r.ReleasedAt).HasColumnName("released_at");

        builder.HasIndex(r => new { r.BookingId, r.Status });
        builder.HasIndex(r => r.TicketId);
    }
}
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Bookings.Infrastructure.Persistence.Configurations;

public sealed class BookingConfiguration : IEntityTypeConfiguration<Booking>
{
    public void Configure(EntityTypeBuilder<Booking> builder)
    {
        builder.ToTable("bookings");
        builder.HasKey(b => b.Id);
        builder.Property(b => b.Id).HasColumnName("id");

        builder.Property(b => b.BookDate).HasColumnName("book_date").IsRequired();

        builder.Property(b => b.Status)
            .HasColumnName("status")
            .HasConversion<int>()
            .IsRequired();

        builder.Property(b => b.BookRef)
            .HasConversion(br => br.Value, v => BookingReference.Create(v))
            .HasColumnName("book_ref")
            .HasMaxLength(6)
            .IsRequired();

        builder.Property(b => b.PassengerId)
            .HasConversion(pid => pid.Value, v => PassengerId.Create(v))
            .HasColumnName("passenger_id")
            .HasMaxLength(20)
            .IsRequired();

        builder.Property(b => b.PassengerName)
            .HasConversion(pn => pn.Value, v => PassengerName.Create(v))
            .HasColumnName("passenger_name")
            .HasMaxLength(200)
            .IsRequired();

        builder.OwnsOne(b => b.TotalAmount, m =>
        {
            m.Property(x => x.Amount).HasColumnName("total_amount").HasPrecision(18, 2).IsRequired();
            m.Property(x => x.Currency).HasColumnName("currency").HasMaxLength(3).IsRequired();
        });

        builder.OwnsMany(b => b.Tickets, t =>
        {
            t.ToTable("tickets");
            t.WithOwner().HasForeignKey("booking_id");
            t.HasKey(x => x.Id);

            // KEY FIX: the Id is generated in code, not by the database.
            // Without ValueGeneratedNever, EF Core treats the new entity as
            // "modified" and issues UPDATE instead of INSERT.
            t.Property(x => x.Id)
                .HasColumnName("id")
                .ValueGeneratedNever();

            t.Property(x => x.TicketNo).HasColumnName("ticket_no").HasMaxLength(20).IsRequired();
            t.Property(x => x.FlightId).HasColumnName("flight_id").IsRequired();
            t.Property(x => x.Amount).HasColumnName("amount").HasPrecision(18, 2).IsRequired();

            t.Property(x => x.PassengerId)
                .HasConversion(pid => pid.Value, v => PassengerId.Create(v))
                .HasColumnName("passenger_id")
                .HasMaxLength(20)
                .IsRequired();

            t.Property(x => x.PassengerName)
                .HasConversion(pn => pn.Value, v => PassengerName.Create(v))
                .HasColumnName("passenger_name")
                .HasMaxLength(200)
                .IsRequired();

            t.HasIndex("booking_id");
        });

        builder.HasIndex(b => b.BookRef).IsUnique();
    }
}
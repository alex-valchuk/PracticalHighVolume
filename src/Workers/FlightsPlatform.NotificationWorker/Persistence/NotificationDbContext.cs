using Microsoft.EntityFrameworkCore;

namespace FlightsPlatform.NotificationWorker.Persistence;

public sealed class NotificationDbContext : DbContext
{
    public const string SchemaName = "notification";

    public NotificationDbContext(DbContextOptions<NotificationDbContext> options)
        : base(options) { }

    public DbSet<ConsumedMessage> ConsumedMessages => Set<ConsumedMessage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(SchemaName);

        modelBuilder.Entity<ConsumedMessage>(b =>
        {
            b.ToTable("consumed_messages");
            b.HasKey(x => x.MessageId);
            b.Property(x => x.MessageId).HasColumnName("message_id").ValueGeneratedNever();
            b.Property(x => x.ConsumedAt).HasColumnName("consumed_at").IsRequired();
        });

        base.OnModelCreating(modelBuilder);
    }
}
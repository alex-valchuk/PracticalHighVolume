using Microsoft.EntityFrameworkCore;

namespace FlightsPlatform.AnalyticsWorker.Persistence;

public sealed class AnalyticsDbContext : DbContext
{
    public const string SchemaName = "analytics";

    public AnalyticsDbContext(DbContextOptions<AnalyticsDbContext> options)
        : base(options) { }

    public DbSet<ConsumedMessage> ConsumedMessages => Set<ConsumedMessage>();
    public DbSet<AuditEntry> AuditEntries => Set<AuditEntry>();

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

        modelBuilder.Entity<AuditEntry>(b =>
        {
            b.ToTable("audit_log");
            b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
            b.Property(x => x.MessageId).HasColumnName("message_id").IsRequired();
            b.Property(x => x.EventType).HasColumnName("event_type").HasMaxLength(200).IsRequired();
            b.Property(x => x.Payload).HasColumnName("payload").IsRequired();
            b.Property(x => x.RecordedAt).HasColumnName("recorded_at").IsRequired();
            b.HasIndex(x => x.EventType);
            b.HasIndex(x => x.RecordedAt);
        });

        base.OnModelCreating(modelBuilder);
    }
}
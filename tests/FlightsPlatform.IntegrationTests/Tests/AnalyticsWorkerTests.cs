using System.Diagnostics;
using FlightsPlatform.AnalyticsWorker.Consumers;
using FlightsPlatform.AnalyticsWorker.Persistence;
using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.Contracts.FlightCatalog;
using FlightsPlatform.IntegrationTests.Fixtures;
using FluentAssertions;
using MassTransit.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace FlightsPlatform.IntegrationTests.Tests;

public sealed class AnalyticsWorkerTests : IClassFixture<PostgresContainerFixture>
{
    private readonly PostgresContainerFixture _pg;

    public AnalyticsWorkerTests(PostgresContainerFixture pg) => _pg = pg;

    private AnalyticsDbContext CreateDb()
    {
        var options = new DbContextOptionsBuilder<AnalyticsDbContext>()
            .UseNpgsql(_pg.ConnectionString, npgsql =>
                npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "analytics"))
            .Options;

        return new AnalyticsDbContext(options);
    }

    private async Task ResetDatabaseAsync()
    {
        await using var db = CreateDb();
        await db.Database.MigrateAsync();
        await db.Database.ExecuteSqlRawAsync(
            "TRUNCATE TABLE analytics.audit_log, analytics.consumed_messages;");
    }

    private static async Task WaitConsumedAsync<T>(
        InMemoryTestHarness harness, int count, int timeoutMs = 5000)
        where T : class
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            if (harness.Consumed.Select<T>().Count() >= count)
                return;
            await Task.Delay(25);
        }

        var actual = harness.Consumed.Select<T>().Count();
        throw new TimeoutException(
            $"Expected {count} consumed {typeof(T).Name} messages, but got {actual} within {timeoutMs}ms.");
    }

    [Fact]
    public async Task Consume_BookingConfirmed_WritesAuditEntry()
    {
        await ResetDatabaseAsync();

        var harness = new InMemoryTestHarness();
        harness.Consumer(() => new BookingConfirmedAuditConsumer(
            CreateDb(),
            NullLogger<BookingConfirmedAuditConsumer>.Instance));

        await harness.Start();
        try
        {
            var evt = new BookingConfirmedIntegrationEvent
            {
                BookingId = Guid.NewGuid(),
                BookingReference = "_AB12CD",
                PassengerId = "1234567890",
                PassengerName = "IVANOV IVAN",
                TotalAmount = 12000m,
                Currency = "RUB",
                TicketCount = 1
            };

            await harness.Bus.Publish(evt);
            await WaitConsumedAsync<BookingConfirmedIntegrationEvent>(harness, 1);

            await using var db = CreateDb();
            var audit = await db.AuditEntries.ToListAsync();
            audit.Should().HaveCount(1);
            audit[0].EventType.Should().Be("BookingConfirmed");
            audit[0].MessageId.Should().Be(evt.EventId);
            audit[0].Payload.Should().Contain("_AB12CD");
            audit[0].Payload.Should().Contain("12000");

            var consumed = await db.ConsumedMessages.ToListAsync();
            consumed.Should().HaveCount(1);
        }
        finally
        {
            await harness.Stop();
        }
    }

    [Fact]
    public async Task Consume_FlightScheduled_WritesAuditEntry()
    {
        await ResetDatabaseAsync();

        var harness = new InMemoryTestHarness();
        harness.Consumer(() => new FlightScheduledAuditConsumer(
            CreateDb(),
            NullLogger<FlightScheduledAuditConsumer>.Instance));

        await harness.Start();
        try
        {
            var evt = new FlightScheduledIntegrationEvent
            {
                FlightId = Guid.NewGuid(),
                FlightNumber = "PG-0421",
                DepartureAirport = "SVO",
                ArrivalAirport = "OVB",
                ScheduledDeparture = DateTimeOffset.UtcNow.AddDays(1),
                ScheduledArrival = DateTimeOffset.UtcNow.AddDays(1).AddHours(4)
            };

            await harness.Bus.Publish(evt);
            await WaitConsumedAsync<FlightScheduledIntegrationEvent>(harness, 1);

            await using var db = CreateDb();
            var audit = await db.AuditEntries.ToListAsync();
            audit.Should().HaveCount(1);
            audit[0].EventType.Should().Be("FlightScheduled");
            audit[0].Payload.Should().Contain("PG-0421");
        }
        finally
        {
            await harness.Stop();
        }
    }

    [Fact]
    public async Task Consume_SameEventTwice_ProducesOneAuditEntry()
    {
        await ResetDatabaseAsync();

        var harness = new InMemoryTestHarness();
        harness.Consumer(() => new BookingExpiredAuditConsumer(
            CreateDb(),
            NullLogger<BookingExpiredAuditConsumer>.Instance));

        await harness.Start();
        try
        {
            var evt = new BookingExpiredIntegrationEvent
            {
                BookingId = Guid.NewGuid(),
                BookingReference = "_XX9999",
                Reason = "Payment failed"
            };

            await harness.Bus.Publish(evt);
            await harness.Bus.Publish(evt);

            await WaitConsumedAsync<BookingExpiredIntegrationEvent>(harness, 2);

            await using var db = CreateDb();
            var audit = await db.AuditEntries.ToListAsync();
            audit.Should().HaveCount(1);

            var consumed = await db.ConsumedMessages.ToListAsync();
            consumed.Should().HaveCount(1);
        }
        finally
        {
            await harness.Stop();
        }
    }
}
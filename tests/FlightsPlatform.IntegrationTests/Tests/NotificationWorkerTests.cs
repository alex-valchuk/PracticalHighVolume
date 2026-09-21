using System.Diagnostics;
using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.IntegrationTests.Fixtures;
using FlightsPlatform.NotificationWorker.Consumers;
using FlightsPlatform.NotificationWorker.Persistence;
using FluentAssertions;
using MassTransit.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace FlightsPlatform.IntegrationTests.Tests;

public sealed class NotificationWorkerTests : IClassFixture<PostgresContainerFixture>
{
    private readonly PostgresContainerFixture _pg;

    public NotificationWorkerTests(PostgresContainerFixture pg) => _pg = pg;

    private NotificationDbContext CreateDb()
    {
        var options = new DbContextOptionsBuilder<NotificationDbContext>()
            .UseNpgsql(_pg.ConnectionString, npgsql =>
                npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "notification"))
            .Options;

        return new NotificationDbContext(options);
    }

    private async Task ResetDatabaseAsync()
    {
        await using var db = CreateDb();
        await db.Database.MigrateAsync();
        await db.Database.ExecuteSqlRawAsync("TRUNCATE TABLE notification.consumed_messages;");
    }

    private static BookingConfirmedIntegrationEvent MakeEvent(string bookingRef = "_AB12CD")
        => new()
        {
            BookingId = Guid.NewGuid(),
            BookingReference = bookingRef,
            PassengerId = "1234567890",
            PassengerName = "IVANOV IVAN",
            TotalAmount = 12000m,
            Currency = "RUB",
            TicketCount = 1
        };

    // Publish is fire-and-forget; wait until N messages have been consumed
    // by the harness before asserting the database state.
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
    public async Task Consume_ValidBookingConfirmed_WritesConsumedMessage()
    {
        await ResetDatabaseAsync();

        var harness = new InMemoryTestHarness();
        harness.Consumer(() => new BookingConfirmedConsumer(
            CreateDb(),
            NullLogger<BookingConfirmedConsumer>.Instance));

        await harness.Start();
        try
        {
            await harness.Bus.Publish(MakeEvent());
            await WaitConsumedAsync<BookingConfirmedIntegrationEvent>(harness, 1);

            await using var db = CreateDb();
            var consumed = await db.ConsumedMessages.ToListAsync();
            consumed.Should().HaveCount(1);
        }
        finally
        {
            await harness.Stop();
        }
    }

    [Fact]
    public async Task Consume_SameMessageTwice_IsIdempotent()
    {
        await ResetDatabaseAsync();

        var harness = new InMemoryTestHarness();
        harness.Consumer(() => new BookingConfirmedConsumer(
            CreateDb(),
            NullLogger<BookingConfirmedConsumer>.Instance));

        await harness.Start();
        try
        {
            var evt = MakeEvent();

            await harness.Bus.Publish(evt);
            await harness.Bus.Publish(evt);

            // Both deliveries are consumed (2nd one is skipped by the idempotency check).
            await WaitConsumedAsync<BookingConfirmedIntegrationEvent>(harness, 2);

            await using var db = CreateDb();
            var consumed = await db.ConsumedMessages.ToListAsync();
            consumed.Should().HaveCount(1);
            consumed[0].MessageId.Should().Be(evt.EventId);
        }
        finally
        {
            await harness.Stop();
        }
    }

    [Fact]
    public async Task Consume_DifferentMessages_ProducesTwoRows()
    {
        await ResetDatabaseAsync();

        var harness = new InMemoryTestHarness();
        harness.Consumer(() => new BookingConfirmedConsumer(
            CreateDb(),
            NullLogger<BookingConfirmedConsumer>.Instance));

        await harness.Start();
        try
        {
            await harness.Bus.Publish(MakeEvent("_AAAAAA"));
            await harness.Bus.Publish(MakeEvent("_BBBBBB"));

            await WaitConsumedAsync<BookingConfirmedIntegrationEvent>(harness, 2);

            await using var db = CreateDb();
            var consumed = await db.ConsumedMessages.ToListAsync();
            consumed.Should().HaveCount(2);
        }
        finally
        {
            await harness.Stop();
        }
    }
}
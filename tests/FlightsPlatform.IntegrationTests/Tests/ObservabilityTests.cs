using System.Diagnostics;
using System.Diagnostics.Metrics;
using FlightsPlatform.Observability;
using FluentAssertions;
using Xunit;

namespace FlightsPlatform.IntegrationTests.Tests;

public sealed class ObservabilityTests
{
    [Fact]
    public void Meters_Expose_All_Business_Counters()
    {
        var recordedCounters = new List<string>();

        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, meterListener) =>
        {
            if (instrument.Meter.Name == Meters.Name)
            {
                recordedCounters.Add(instrument.Name);
                meterListener.EnableMeasurementEvents(instrument);
            }
        };
        listener.Start();

        // Trigger some writes so the instruments are published
        Meters.BookingsConfirmed.Add(1);
        Meters.BookingsExpired.Add(1);
        Meters.BookingsCancelled.Add(1);
        Meters.FlightsScheduled.Add(1);
        Meters.CacheHits.Add(1);
        Meters.CacheMisses.Add(1);
        Meters.SagaDuration.Record(42);

        recordedCounters.Should().Contain("bookings.confirmed");
        recordedCounters.Should().Contain("bookings.expired");
        recordedCounters.Should().Contain("bookings.cancelled");
        recordedCounters.Should().Contain("flights.scheduled");
        recordedCounters.Should().Contain("cache.hits");
        recordedCounters.Should().Contain("cache.misses");
        recordedCounters.Should().Contain("saga.duration");
    }

    [Fact]
    public void ActivitySources_Are_Defined()
    {
        ActivitySources.Name.Should().Be("FlightsPlatform");
        ActivitySources.Commands.Name.Should().Be("FlightsPlatform.Commands");
        ActivitySources.Saga.Name.Should().Be("FlightsPlatform.Saga");
        ActivitySources.Cache.Name.Should().Be("FlightsPlatform.Cache");

        ActivitySources.All().Should().HaveCount(4);
    }

    [Fact]
    public void ActivitySource_Can_Create_Activity_When_Listener_Attached()
    {
        Activity? captured = null;

        using var listener = new ActivityListener
        {
            ShouldListenTo = source => source.Name == ActivitySources.Saga.Name,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllData,
            ActivityStarted = activity => { captured = activity; }
        };
        ActivitySource.AddActivityListener(listener);

        using var activity = ActivitySources.Saga.Instance.StartActivity("saga.test_step");

        activity.Should().NotBeNull();
        captured.Should().NotBeNull();
        captured!.OperationName.Should().Be("saga.test_step");
    }
}
using FlightCatalog.Domain;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class FlightAggregateTests
{
    private static Flight CreateFlight()
    {
        var now = DateTimeOffset.UtcNow;
        return Flight.ScheduleFlight(
            FlightNumber.Create("PG-0001"),
            Route.Create(AirportCode.Create("SVO"), AirportCode.Create("OVB")),
            Schedule.Create(now.AddDays(1), now.AddDays(1).AddHours(4)),
            "Airbus A320");
    }

    [Fact]
    public void ScheduleFlight_RaisesFlightScheduledEvent()
    {
        var flight = CreateFlight();
        flight.DomainEvents.Should().ContainSingle(e => e is FlightScheduled);
        flight.Status.Should().Be(FlightStatus.Scheduled);
    }

    [Fact]
    public void Delay_WithinReasonableWindow_RaisesFlightDelayed()
    {
        var flight = CreateFlight();
        flight.ClearDomainEvents();

        var newDep = flight.Schedule.Departure.AddHours(1);
        flight.Delay(newDep, flight.Schedule.Arrival.AddHours(1));

        flight.Status.Should().Be(FlightStatus.Delayed);
        var evt = flight.DomainEvents.OfType<FlightDelayed>().Single();
        evt.IsSignificant.Should().BeFalse();
    }

    [Fact]
    public void Delay_MoreThanThreeHours_MarksSignificant()
    {
        var flight = CreateFlight();
        flight.ClearDomainEvents();

        var newDep = flight.Schedule.Departure.AddHours(5);
        flight.Delay(newDep, flight.Schedule.Arrival.AddHours(5));

        var evt = flight.DomainEvents.OfType<FlightDelayed>().Single();
        evt.IsSignificant.Should().BeTrue();
    }

    [Fact]
    public void Cancel_OnScheduledFlight_SucceedsAndRaisesEvent()
    {
        var flight = CreateFlight();
        flight.ClearDomainEvents();

        flight.Cancel("weather");

        flight.Status.Should().Be(FlightStatus.Cancelled);
        flight.DomainEvents.Should().ContainSingle(e => e is FlightCancelled);
    }

    [Fact]
    public void Cancel_OnAlreadyCancelled_Throws()
    {
        var flight = CreateFlight();
        flight.Cancel("weather");

        var act = () => flight.Cancel("duplicate");
        act.Should().Throw<DomainException>();
    }
}
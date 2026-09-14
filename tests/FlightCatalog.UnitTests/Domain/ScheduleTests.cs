using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class ScheduleTests
{
    [Fact]
    public void Create_WithValidTimes_Succeeds()
    {
        var now = DateTimeOffset.UtcNow;
        var schedule = Schedule.Create(now, now.AddHours(3));
        schedule.Arrival.Should().BeAfter(schedule.Departure);
    }

    [Fact]
    public void Create_WithArrivalBeforeDeparture_Throws()
    {
        var now = DateTimeOffset.UtcNow;
        var act = () => Schedule.Create(now, now.AddHours(-1));
        act.Should().Throw<DomainException>();
    }
}
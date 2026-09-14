using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class RouteTests
{
    [Fact]
    public void Create_WithDifferentAirports_Succeeds()
    {
        var route = Route.Create(AirportCode.Create("SVO"), AirportCode.Create("OVB"));
        route.Departure.Value.Should().Be("SVO");
        route.Arrival.Value.Should().Be("OVB");
    }

    [Fact]
    public void Create_WithSameAirport_Throws()
    {
        var act = () => Route.Create(AirportCode.Create("SVO"), AirportCode.Create("SVO"));
        act.Should().Throw<DomainException>();
    }
}
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class AirportTests
{
    private static Airport Make() =>
        Airport.Create(
            AirportCode.Create("SVO"),
            "Sheremetyevo",
            "Moscow",
            "Europe/Moscow",
            Coordinates.Create(55.97, 37.41));

    [Fact]
    public void Create_Valid_RaisesEvent()
    {
        var a = Make();
        a.DomainEvents.Should().ContainSingle(e => e is AirportSynced);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_EmptyName_Throws(string name)
    {
        var act = () => Airport.Create(
            AirportCode.Create("SVO"), name, "Moscow", "Europe/Moscow",
            Coordinates.Create(55.97, 37.41));
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void UpdateInfo_ChangesFields()
    {
        var a = Make();
        a.UpdateInfo("NewName", "NewCity", "UTC", Coordinates.Create(0, 0));
        a.Name.Should().Be("NewName");
        a.City.Should().Be("NewCity");
        a.Timezone.Should().Be("UTC");
    }
}
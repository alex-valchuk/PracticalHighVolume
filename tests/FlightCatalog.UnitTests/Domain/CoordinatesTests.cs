using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class CoordinatesTests
{
    [Fact]
    public void Create_WithValidValues_Succeeds()
    {
        var c = Coordinates.Create(55.97, 37.41);
        c.Latitude.Should().Be(55.97);
        c.Longitude.Should().Be(37.41);
    }

    [Theory]
    [InlineData(91, 0)]
    [InlineData(-91, 0)]
    [InlineData(0, 181)]
    [InlineData(0, -181)]
    public void Create_OutOfRange_Throws(double lat, double lon)
    {
        var act = () => Coordinates.Create(lat, lon);
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void Parse_PostgresPointLiteral_Succeeds()
    {
        var c = Coordinates.Parse("(37.41,55.97)");
        c.Longitude.Should().BeApproximately(37.41, 0.0001);
        c.Latitude.Should().BeApproximately(55.97, 0.0001);
    }

    [Theory]
    [InlineData("")]
    [InlineData("garbage")]
    [InlineData("(1)")]
    public void Parse_Invalid_Throws(string raw)
    {
        var act = () => Coordinates.Parse(raw);
        act.Should().Throw<DomainException>();
    }
}
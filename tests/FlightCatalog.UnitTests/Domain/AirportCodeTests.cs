using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class AirportCodeTests
{
    [Theory]
    [InlineData("SVO")]
    [InlineData("svo")]
    [InlineData(" OVB ")]
    public void Create_WithValidInput_NormalizesAndSucceeds(string input)
    {
        var code = AirportCode.Create(input);
        code.Value.Should().Be(input.Trim().ToUpperInvariant());
    }

    [Theory]
    [InlineData("")]
    [InlineData("AB")]
    [InlineData("ABCD")]
    [InlineData("S1O")]
    public void Create_WithInvalidInput_Throws(string input)
    {
        var act = () => AirportCode.Create(input);
        act.Should().Throw<DomainException>();
    }
}
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Domain;

public class FlightNumberTests
{
    [Theory]
    [InlineData("PG-0421")]
    [InlineData("pg-421")]
    [InlineData("AA-1234")]
    public void Create_WithValidInput_Succeeds(string input)
    {
        var number = FlightNumber.Create(input);
        number.Value.Should().StartWith(input[..2].ToUpperInvariant());
    }

    [Theory]
    [InlineData("")]
    [InlineData("PG0421")]
    [InlineData("P-0421")]
    [InlineData("PG-ABCD")]
    [InlineData("PG-12345")]
    public void Create_WithInvalidInput_Throws(string input)
    {
        var act = () => FlightNumber.Create(input);
        act.Should().Throw<DomainException>();
    }
}
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingReferenceTests
{
    [Theory]
    [InlineData("ABC123")]
    [InlineData("abc123")]
    [InlineData(" ABC123 ")]
    public void Create_Valid_Normalizes(string input)
    {
        var r = BookingReference.Create(input);
        r.Value.Should().Be("ABC123");
    }

    [Theory]
    [InlineData("")]
    [InlineData("ABC12")]
    [InlineData("ABC1234")]
    [InlineData("ABC-12")]
    public void Create_Invalid_Throws(string input)
    {
        var act = () => BookingReference.Create(input);
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void Generate_ProducesValid()
    {
        var r = BookingReference.Generate();
        r.Value.Should().HaveLength(6);
        r.Value.Should().MatchRegex("^[A-Z0-9]{6}$");
    }
}
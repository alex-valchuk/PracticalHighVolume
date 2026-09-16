using FlightsPlatform.Application.Abstractions;
using FluentAssertions;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class CacheKeysTests
{
    [Fact]
    public void Airport_Key_Format_Is_Deterministic_And_Uppercase()
    {
        var expected = "flight-catalog:airport:SVO";

        CacheKeys.Airport("svo").Should().Be(expected);
        CacheKeys.Airport("SVO").Should().Be(expected);
    }

    [Fact]
    public void Airport_Key_Trims_Whitespace_For_Safety()
    {
        // CacheKeys defends against accidental whitespace from callers
        // (e.g. URL decoding produces "%20SVO%20" -> " SVO ").
        CacheKeys.Airport(" SVO ").Should().Be("flight-catalog:airport:SVO");
    }

    [Fact]
    public void Flight_Key_Uses_Full_Guid()
    {
        var id = Guid.Parse("22222222-2222-2222-2222-222222222222");
        CacheKeys.Flight(id).Should().Be("flight-catalog:flight:22222222-2222-2222-2222-222222222222");
    }

    [Fact]
    public void BookingLock_Key_Format()
    {
        var id = Guid.Parse("33333333-3333-3333-3333-333333333333");
        CacheKeys.BookingLock(id).Should().Be("bookings:booking:33333333-3333-3333-3333-333333333333:write");
    }
}
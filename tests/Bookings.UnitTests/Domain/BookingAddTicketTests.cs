using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingAddTicketTests
{
    private static Booking Make()
        => Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static PassengerId OtherPassenger() => PassengerId.Create("9999999999");
    private static PassengerName OtherName() => PassengerName.Create("PETROV PETR");

    [Fact]
    public void AddTicket_ToPendingBooking_SucceedsAndUpdatesTotal()
    {
        var booking = Make();
        booking.ClearDomainEvents();
        var flightId = Guid.NewGuid();

        var ticketId = booking.AddTicket(
            OtherPassenger(), OtherName(), flightId, 12500m);

        ticketId.Should().NotBeEmpty();
        booking.Tickets.Should().HaveCount(1);
        booking.TotalAmount.Amount.Should().Be(12500m);
        booking.TotalAmount.Currency.Should().Be("RUB");
        booking.DomainEvents.Should().ContainSingle(e => e is TicketAdded);
    }

    [Fact]
    public void AddTicket_Twice_SumsTotal()
    {
        var booking = Make();
        var flight1 = Guid.NewGuid();
        var flight2 = Guid.NewGuid();

        booking.AddTicket(OtherPassenger(), OtherName(), flight1, 10000m);
        booking.AddTicket(PassengerId.Create("5555555555"),
                          PassengerName.Create("SIDOROV S"),
                          flight2, 7500m);

        booking.TotalAmount.Amount.Should().Be(17500m);
    }

    [Fact]
    public void AddTicket_DuplicatePassengerOnSameFlight_Throws()
    {
        var booking = Make();
        var flightId = Guid.NewGuid();
        var passenger = OtherPassenger();

        booking.AddTicket(passenger, OtherName(), flightId, 10000m);

        var act = () => booking.AddTicket(passenger, OtherName(), flightId, 10000m);
        act.Should().Throw<DomainException>()
            .WithMessage("*already on flight*");
    }

    [Fact]
    public void AddTicket_SamePassengerOnDifferentFlights_Allowed()
    {
        var booking = Make();
        var passenger = OtherPassenger();

        booking.AddTicket(passenger, OtherName(), Guid.NewGuid(), 10000m);
        booking.AddTicket(passenger, OtherName(), Guid.NewGuid(), 10000m);

        booking.Tickets.Should().HaveCount(2);
    }

    [Fact]
    public void AddTicket_ZeroAmount_Throws()
    {
        var booking = Make();
        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 0m);
        act.Should().Throw<DomainException>().WithMessage("*must be positive*");
    }

    [Fact]
    public void AddTicket_NegativeAmount_Throws()
    {
        var booking = Make();
        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), -1m);
        act.Should().Throw<DomainException>().WithMessage("*must be positive*");
    }

    [Fact]
    public void AddTicket_EmptyFlightId_Throws()
    {
        var booking = Make();
        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.Empty, 100m);
        act.Should().Throw<DomainException>().WithMessage("*FlightId*");
    }

    [Fact]
    public void AddTicket_OnConfirmedBooking_Throws()
    {
        var booking = Make();
        booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 10000m);
        booking.Confirm();

        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 10000m);
        act.Should().Throw<DomainException>().WithMessage("*not Pending*");
    }

    [Fact]
    public void AddTicket_OnCancelledBooking_Throws()
    {
        var booking = Make();
        booking.Cancel("test");

        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 10000m);
        act.Should().Throw<DomainException>().WithMessage("*not Pending*");
    }
}
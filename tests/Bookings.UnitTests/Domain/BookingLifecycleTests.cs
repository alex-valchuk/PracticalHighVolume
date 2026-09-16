using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingLifecycleTests
{
    private static Booking Make() =>
        Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static void AddOneTicket(Booking b)
        => b.AddTicket(
            PassengerId.Create("9999999999"),
            PassengerName.Create("PETROV PETR"),
            Guid.NewGuid(),
            10000m);

    [Fact]
    public void Confirm_WithTickets_Succeeds()
    {
        var b = Make();
        AddOneTicket(b);
        b.ClearDomainEvents();

        b.Confirm();

        b.Status.Should().Be(BookingStatus.Confirmed);
        b.DomainEvents.Should().ContainSingle(e => e is BookingConfirmed);
    }

    [Fact]
    public void Confirm_WithoutTickets_Throws()
    {
        var b = Make();
        var act = () => b.Confirm();
        act.Should().Throw<DomainException>().WithMessage("*without tickets*");
    }

    [Fact]
    public void Confirm_OnAlreadyConfirmed_Throws()
    {
        var b = Make();
        AddOneTicket(b);
        b.Confirm();

        var act = () => b.Confirm();
        act.Should().Throw<DomainException>().WithMessage("*already confirmed*");
    }

    [Fact]
    public void MarkExpired_OnPending_Succeeds()
    {
        var b = Make();
        b.ClearDomainEvents();

        b.MarkExpired("payment failed");

        b.Status.Should().Be(BookingStatus.Expired);
        b.DomainEvents.Should().ContainSingle(e => e is BookingExpired);
    }

    [Fact]
    public void MarkExpired_OnConfirmed_Throws()
    {
        var b = Make();
        AddOneTicket(b);
        b.Confirm();

        var act = () => b.MarkExpired("late");
        act.Should().Throw<DomainException>().WithMessage("*Cannot expire*");
    }

    [Fact]
    public void MarkExpired_EmptyReason_Throws()
    {
        var b = Make();
        var act = () => b.MarkExpired("");
        act.Should().Throw<DomainException>().WithMessage("*reason*");
    }
}
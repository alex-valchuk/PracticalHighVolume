using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingTests
{
    private static Booking Make() =>
        Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    [Fact]
    public void CreateDraft_RaisesEvent()
    {
        var b = Make();
        b.DomainEvents.Should().ContainSingle(e => e is BookingCreated);
        b.Status.Should().Be(BookingStatus.Pending);
        b.TotalAmount.Amount.Should().Be(0);
        b.TotalAmount.Currency.Should().Be("RUB");
    }

    [Fact]
    public void Cancel_OnPending_Succeeds()
    {
        var b = Make();
        b.ClearDomainEvents();

        b.Cancel("changed plans");

        b.Status.Should().Be(BookingStatus.Cancelled);
        b.DomainEvents.Should().ContainSingle(e => e is BookingCancelled);
    }

    [Fact]
    public void Cancel_OnCancelled_Throws()
    {
        var b = Make();
        b.Cancel("first");

        var act = () => b.Cancel("second");
        act.Should().Throw<DomainException>();
    }
}
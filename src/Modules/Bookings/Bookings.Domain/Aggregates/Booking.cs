using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class Booking : AggregateRoot<Guid>
{
    private readonly List<Ticket> _tickets = new();

    public BookingReference BookRef { get; private set; } = default!;
    public DateTimeOffset BookDate { get; private set; }
    public Money TotalAmount { get; private set; } = default!;
    public BookingStatus Status { get; private set; }
    public PassengerId PassengerId { get; private set; } = default!;
    public PassengerName PassengerName { get; private set; } = default!;

    public IReadOnlyCollection<Ticket> Tickets => _tickets.AsReadOnly();

    private Booking() { }

    private Booking(
        Guid id,
        BookingReference bookRef,
        DateTimeOffset bookDate,
        Money totalAmount,
        PassengerId passengerId,
        PassengerName passengerName) : base(id)
    {
        BookRef = bookRef;
        BookDate = bookDate;
        TotalAmount = totalAmount;
        Status = BookingStatus.Pending;
        PassengerId = passengerId;
        PassengerName = passengerName;
    }

    public static Booking CreateDraft(
        PassengerId passengerId,
        PassengerName passengerName,
        string currency)
    {
        var booking = new Booking(
            Guid.NewGuid(),
            BookingReference.Generate(),
            DateTimeOffset.UtcNow,
            Money.Zero(currency),
            passengerId,
            passengerName);

        booking.Raise(new BookingCreated(
            booking.Id,
            booking.BookRef.Value,
            passengerId.Value,
            currency.ToUpperInvariant()));

        return booking;
    }

    public void Cancel(string reason)
    {
        if (Status == BookingStatus.Cancelled)
            throw new DomainException("Booking is already cancelled.");

        if (Status == BookingStatus.Confirmed)
            throw new DomainException("Cannot cancel a confirmed booking. Use refund flow.");

        if (string.IsNullOrWhiteSpace(reason))
            throw new DomainException("Cancellation reason is required.");

        Status = BookingStatus.Cancelled;
        Raise(new BookingCancelled(Id, BookRef.Value, reason));
    }
}
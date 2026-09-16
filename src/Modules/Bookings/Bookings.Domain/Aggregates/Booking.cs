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

    public Guid AddTicket(
        PassengerId passengerId,
        PassengerName passengerName,
        Guid flightId,
        decimal amount)
    {
        if (Status != BookingStatus.Pending)
            throw new DomainException(
                "Cannot add a ticket to a booking that is not Pending. Current status: " + Status);

        if (flightId == Guid.Empty)
            throw new DomainException("FlightId is required.");

        if (amount <= 0)
            throw new DomainException("Ticket amount must be positive.");

        var duplicate = _tickets.Any(t =>
            t.FlightId == flightId && t.PassengerId == passengerId);

        if (duplicate)
            throw new DomainException(
                "Passenger " + passengerId.Value + " is already on flight " + flightId);

        var ticketNo = Guid.NewGuid().ToString("N").Substring(0, 13);
        var ticket = new Ticket(
            Guid.NewGuid(),
            ticketNo,
            passengerId,
            passengerName,
            flightId,
            amount);

        _tickets.Add(ticket);

        TotalAmount = TotalAmount.Add(Money.Create(amount, TotalAmount.Currency));

        Raise(new TicketAdded(
            Id,
            ticket.Id,
            flightId,
            amount,
            TotalAmount.Currency));

        return ticket.Id;
    }

    public void Confirm()
    {
        if (Status == BookingStatus.Confirmed)
            throw new DomainException("Booking is already confirmed.");

        if (Status != BookingStatus.Pending)
            throw new DomainException(
                "Cannot confirm a booking in status " + Status + ".");

        if (_tickets.Count == 0)
            throw new DomainException("Cannot confirm a booking without tickets.");

        Status = BookingStatus.Confirmed;

        Raise(new BookingConfirmed(
            Id,
            BookRef.Value,
            TotalAmount.Amount,
            TotalAmount.Currency));
    }

    public void MarkExpired(string reason)
    {
        if (Status != BookingStatus.Pending)
            throw new DomainException(
                "Cannot expire a booking in status " + Status + ".");

        if (string.IsNullOrWhiteSpace(reason))
            throw new DomainException("Expiration reason is required.");

        Status = BookingStatus.Expired;

        Raise(new BookingExpired(Id, BookRef.Value, reason));
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
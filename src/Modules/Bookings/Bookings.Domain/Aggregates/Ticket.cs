using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class Ticket : Entity<Guid>
{
    public string TicketNo { get; private set; } = default!;
    public PassengerId PassengerId { get; private set; } = default!;
    public PassengerName PassengerName { get; private set; } = default!;
    public Guid FlightId { get; private set; }
    public decimal Amount { get; private set; }

    private Ticket() { }

    internal Ticket(
        Guid id,
        string ticketNo,
        PassengerId passengerId,
        PassengerName passengerName,
        Guid flightId,
        decimal amount) : base(id)
    {
        TicketNo = ticketNo;
        PassengerId = passengerId;
        PassengerName = passengerName;
        FlightId = flightId;
        Amount = amount;
    }
}
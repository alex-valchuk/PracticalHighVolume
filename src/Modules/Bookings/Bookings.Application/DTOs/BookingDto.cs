namespace Bookings.Application.DTOs;

public sealed class BookingDto
{
    public Guid Id { get; init; }
    public string BookRef { get; init; } = default!;
    public DateTimeOffset BookDate { get; init; }
    public decimal TotalAmount { get; init; }
    public string Currency { get; init; } = default!;
    public int Status { get; init; }
    public string PassengerId { get; init; } = default!;
    public string PassengerName { get; init; } = default!;
    public List<TicketDto> Tickets { get; init; } = new();
}

public sealed class TicketDto
{
    public Guid Id { get; init; }
    public string TicketNo { get; init; } = default!;
    public Guid FlightId { get; init; }
    public decimal Amount { get; init; }
}
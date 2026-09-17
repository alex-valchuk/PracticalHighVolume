using FlightsPlatform.Contracts.Common;

namespace FlightsPlatform.Contracts.Bookings;

public sealed record BookingConfirmedIntegrationEvent : IntegrationEventBase
{
    public Guid BookingId { get; init; }
    public string BookingReference { get; init; } = default!;
    public string PassengerId { get; init; } = default!;
    public string PassengerName { get; init; } = default!;
    public decimal TotalAmount { get; init; }
    public string Currency { get; init; } = default!;
    public int TicketCount { get; init; }
}
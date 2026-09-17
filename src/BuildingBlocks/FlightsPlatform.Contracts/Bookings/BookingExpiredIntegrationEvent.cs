using FlightsPlatform.Contracts.Common;

namespace FlightsPlatform.Contracts.Bookings;

public sealed record BookingExpiredIntegrationEvent : IntegrationEventBase
{
    public Guid BookingId { get; init; }
    public string BookingReference { get; init; } = default!;
    public string Reason { get; init; } = default!;
}
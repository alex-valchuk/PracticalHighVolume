using FlightsPlatform.Contracts.Common;

namespace FlightsPlatform.Contracts.Bookings;

public sealed record BookingCreatedIntegrationEvent : IntegrationEventBase
{
    public Guid BookingId { get; init; }
    public string BookingReference { get; init; } = default!;
    public string PassengerId { get; init; } = default!;
    public string Currency { get; init; } = default!;
}
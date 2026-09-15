namespace Bookings.Api.Contracts;

public sealed record CreateBookingRequest(
    string PassengerId,
    string PassengerName,
    string Currency);
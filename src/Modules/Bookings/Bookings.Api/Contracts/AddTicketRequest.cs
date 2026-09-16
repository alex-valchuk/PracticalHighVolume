namespace Bookings.Api.Contracts;

public sealed record AddTicketRequest(
    Guid FlightId,
    string PassengerId,
    string PassengerName,
    decimal Amount);
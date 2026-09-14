namespace FlightCatalog.Api.Contracts;

public sealed record ScheduleFlightRequest(
    string FlightNumber,
    string DepartureAirport,
    string ArrivalAirport,
    DateTimeOffset Departure,
    DateTimeOffset Arrival,
    string AircraftModel);
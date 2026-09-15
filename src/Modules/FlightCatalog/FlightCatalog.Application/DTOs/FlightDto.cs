namespace FlightCatalog.Application.DTOs;

public sealed class FlightDto
{
    public Guid Id { get; init; }
    public string FlightNumber { get; init; } = default!;
    public string DepartureAirport { get; init; } = default!;
    public string? DepartureAirportName { get; init; }
    public string ArrivalAirport { get; init; } = default!;
    public string? ArrivalAirportName { get; init; }
    public DateTimeOffset ScheduledDeparture { get; init; }
    public DateTimeOffset ScheduledArrival { get; init; }
    public int Status { get; init; }
    public string AircraftModel { get; init; } = default!;
}
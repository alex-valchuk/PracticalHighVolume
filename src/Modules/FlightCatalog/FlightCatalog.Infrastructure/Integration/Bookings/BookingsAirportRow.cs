namespace FlightCatalog.Infrastructure.Integration.Bookings;

internal sealed class BookingsAirportRow
{
    public string AirportCode { get; init; } = default!;
    public string AirportName { get; init; } = default!;
    public string City { get; init; } = default!;
    public string Timezone { get; init; } = default!;
    public string Coordinates { get; init; } = default!;
}
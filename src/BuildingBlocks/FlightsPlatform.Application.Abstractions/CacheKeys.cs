namespace FlightsPlatform.Application.Abstractions;

public static class CacheKeys
{
    public const string AirportPrefix = "flight-catalog:airport:";
    public const string FlightPrefix  = "flight-catalog:flight:";

    public static string Airport(string code) => AirportPrefix + Normalize(code);
    public static string Flight(Guid id)      => FlightPrefix + id.ToString("D");
    public static string BookingLock(Guid id) => "bookings:booking:" + id.ToString("D") + ":write";

    private static string Normalize(string value) => value.Trim().ToUpperInvariant();
}
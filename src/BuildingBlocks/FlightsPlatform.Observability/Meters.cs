using System.Diagnostics.Metrics;

namespace FlightsPlatform.Observability;

public static class Meters
{
    public const string Name = "FlightsPlatform";
    public static readonly Meter Instance = new(Name);

    public static readonly Counter<long> BookingsConfirmed =
        Instance.CreateCounter<long>("bookings.confirmed", "count", "Confirmed bookings");

    public static readonly Counter<long> BookingsExpired =
        Instance.CreateCounter<long>("bookings.expired", "count", "Expired bookings");

    public static readonly Counter<long> BookingsCancelled =
        Instance.CreateCounter<long>("bookings.cancelled", "count", "Cancelled bookings");

    public static readonly Counter<long> FlightsScheduled =
        Instance.CreateCounter<long>("flights.scheduled", "count", "Scheduled flights");

    public static readonly Histogram<double> SagaDuration =
        Instance.CreateHistogram<double>("saga.duration", "ms", "Saga execution duration");

    public static readonly Counter<long> CacheHits =
        Instance.CreateCounter<long>("cache.hits", "count", "Cache hits");

    public static readonly Counter<long> CacheMisses =
        Instance.CreateCounter<long>("cache.misses", "count", "Cache misses");
}
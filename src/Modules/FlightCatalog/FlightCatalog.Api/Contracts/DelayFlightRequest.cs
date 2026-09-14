namespace FlightCatalog.Api.Contracts;

public sealed record DelayFlightRequest(
    DateTimeOffset NewDeparture,
    DateTimeOffset NewArrival);
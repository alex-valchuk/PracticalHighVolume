namespace FlightCatalog.Application.Abstractions;

public sealed record ExternalAirport(
    string Code,
    string Name,
    string City,
    string Timezone,
    string Coordinates);

public interface IBookingsSourceReader
{
    Task<IReadOnlyList<ExternalAirport>> ReadAirportsAsync(CancellationToken ct = default);
}
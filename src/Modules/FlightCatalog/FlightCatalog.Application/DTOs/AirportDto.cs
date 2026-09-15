namespace FlightCatalog.Application.DTOs;

public sealed class AirportDto
{
    public Guid Id { get; init; }
    public string Code { get; init; } = default!;
    public string Name { get; init; } = default!;
    public string City { get; init; } = default!;
    public string Timezone { get; init; } = default!;
    public double Latitude { get; init; }
    public double Longitude { get; init; }
}
using Bookings.Application.Abstractions;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Bookings.Infrastructure.External;

/// <summary>
/// Phase 9: HTTP implementation of <see cref="IFlightCatalogClient"/>.
/// Replaces the previous in-process MediatR-based implementation
/// after FlightCatalog was extracted into its own service.
///
/// The DTO mirror below is intentionally local: Bookings.Infrastructure
/// must not reference FlightCatalog.Application types, otherwise the
/// module boundary is broken. Field names match FlightDto on the wire.
/// </summary>
public sealed class HttpFlightCatalogClient : IFlightCatalogClient
{
    private readonly HttpClient _http;

    public HttpFlightCatalogClient(HttpClient http)
    {
        _http = http;
    }

    public async Task<FlightSummary?> GetFlightAsync(Guid flightId, CancellationToken ct = default)
    {
        using var response = await _http.GetAsync($"flight-catalog/flights/{flightId}", ct);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();

        var dto = await response.Content.ReadFromJsonAsync<FlightDtoResponse>(cancellationToken: ct);
        if (dto is null)
        {
            return null;
        }

        return new FlightSummary(
            dto.Id,
            dto.FlightNumber,
            dto.DepartureAirport,
            dto.ArrivalAirport,
            dto.ScheduledDeparture,
            dto.ScheduledArrival,
            dto.Status);
    }

    /// <summary>
    /// Wire shape of FlightCatalog.Application.DTOs.FlightDto. Only the
    /// fields we actually need for the mapping are declared.
    /// </summary>
    private sealed class FlightDtoResponse
    {
        public Guid Id { get; init; }
        public string FlightNumber { get; init; } = default!;
        public string DepartureAirport { get; init; } = default!;
        public string ArrivalAirport { get; init; } = default!;
        public DateTimeOffset ScheduledDeparture { get; init; }
        public DateTimeOffset ScheduledArrival { get; init; }
        public int Status { get; init; }
    }
}
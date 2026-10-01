using System.Net.Http.Json;

namespace FlightsPlatform.Api.External;

public sealed record DashboardCounters(int Flights, int Airports);

/// <summary>
/// Phase 9: reads FlightCatalog-owned counters over HTTP from the
/// extracted FlightCatalog.Service. Replaces direct access to
/// FlightCatalogDbContext from the host's dashboard endpoint.
/// </summary>
public sealed class FlightCatalogDashboardClient
{
    private readonly HttpClient _http;

    public FlightCatalogDashboardClient(HttpClient http)
    {
        _http = http;
    }

    public string HttpBaseAddress => _http.BaseAddress?.ToString() ?? "(null)";

    public async Task<DashboardCounters> GetCountersAsync(CancellationToken ct)
    {
        var dto = await _http.GetFromJsonAsync<DashboardCounters>(
            "internal/dashboard/counters", ct);
        return dto ?? new DashboardCounters(0, 0);
    }
}
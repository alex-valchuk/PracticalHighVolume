using Bookings.Application.Abstractions;
using FlightCatalog.Application.Queries.GetFlightById;
using MediatR;

namespace Bookings.Infrastructure.Integration.FlightCatalog;

/// <summary>
/// Adapter that calls the FlightCatalog module via MediatR.
/// This is the only place in Bookings.Infrastructure that knows
/// about FlightCatalog.Application contracts.
/// </summary>
internal sealed class FlightCatalogClient : IFlightCatalogClient
{
    private readonly IMediator _mediator;

    public FlightCatalogClient(IMediator mediator) => _mediator = mediator;

    public async Task<FlightSummary?> GetFlightAsync(Guid flightId, CancellationToken ct = default)
    {
        var dto = await _mediator.Send(new GetFlightByIdQuery(flightId), ct);
        if (dto is null) return null;

        return new FlightSummary(
            dto.Id,
            dto.FlightNumber,
            dto.DepartureAirport,
            dto.ArrivalAirport,
            dto.ScheduledDeparture,
            dto.ScheduledArrival,
            dto.Status);
    }
}
using FlightCatalog.Application.Abstractions;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Application.Commands.ScheduleFlight;

public sealed class ScheduleFlightCommandHandler : IRequestHandler<ScheduleFlightCommand, Result<Guid>>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<ScheduleFlightCommandHandler> _logger;

    public ScheduleFlightCommandHandler(
        IFlightRepository repository,
        IUnitOfWork unitOfWork,
        ILogger<ScheduleFlightCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    public async Task<Result<Guid>> Handle(ScheduleFlightCommand request, CancellationToken ct)
    {
        try
        {
            var flightNumber = FlightNumber.Create(request.FlightNumber);
            var route = Route.Create(
                AirportCode.Create(request.DepartureAirport),
                AirportCode.Create(request.ArrivalAirport));
            var schedule = Schedule.Create(request.Departure, request.Arrival);

            var flight = Flight.ScheduleFlight(flightNumber, route, schedule, request.AircraftModel);

            await _repository.AddAsync(flight, ct);
            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation("Scheduled flight {FlightId} ({FlightNumber})",
                flight.Id, flight.FlightNumber.Value);

            return Result<Guid>.Success(flight.Id);
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "Domain rule violated while scheduling flight");
            return Result<Guid>.Failure(ex.Message, "domain_error");
        }
    }
}
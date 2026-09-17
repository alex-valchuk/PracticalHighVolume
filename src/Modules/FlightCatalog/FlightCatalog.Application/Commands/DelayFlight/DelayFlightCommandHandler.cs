using FlightCatalog.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Contracts.FlightCatalog;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Application.Commands.DelayFlight;

public sealed class DelayFlightCommandHandler : IRequestHandler<DelayFlightCommand, Result>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIntegrationEventPublisher _publisher;
    private readonly ILogger<DelayFlightCommandHandler> _logger;

    public DelayFlightCommandHandler(
        IFlightRepository repository,
        IUnitOfWork unitOfWork,
        IIntegrationEventPublisher publisher,
        ILogger<DelayFlightCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _publisher = publisher;
        _logger = logger;
    }

    public async Task<Result> Handle(DelayFlightCommand request, CancellationToken ct)
    {
        var flight = await _repository.GetByIdAsync(request.FlightId, ct);
        if (flight is null)
            return Result.Failure("Flight not found", "not_found");

        var oldDeparture = flight.Schedule.Departure;

        try
        {
            flight.Delay(request.NewDeparture, request.NewArrival);
        }
        catch (DomainException ex)
        {
            return Result.Failure(ex.Message, "domain_error");
        }

        _repository.Update(flight);

        await _publisher.PublishAsync(new FlightDelayedIntegrationEvent
        {
            FlightId = flight.Id,
            FlightNumber = flight.FlightNumber.Value,
            OldDeparture = oldDeparture,
            NewDeparture = request.NewDeparture,
            IsSignificant = (request.NewDeparture - oldDeparture) >= TimeSpan.FromHours(3)
        }, ct);

        await _unitOfWork.SaveChangesAsync(ct);

        _logger.LogInformation("Delayed flight {FlightId}", flight.Id);

        return Result.Success();
    }
}
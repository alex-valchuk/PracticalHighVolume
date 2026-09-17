using FlightCatalog.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Contracts.FlightCatalog;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed class CancelFlightCommandHandler : IRequestHandler<CancelFlightCommand, Result>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIntegrationEventPublisher _publisher;
    private readonly ILogger<CancelFlightCommandHandler> _logger;

    public CancelFlightCommandHandler(
        IFlightRepository repository,
        IUnitOfWork unitOfWork,
        IIntegrationEventPublisher publisher,
        ILogger<CancelFlightCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _publisher = publisher;
        _logger = logger;
    }

    public async Task<Result> Handle(CancelFlightCommand request, CancellationToken ct)
    {
        var flight = await _repository.GetByIdAsync(request.FlightId, ct);
        if (flight is null)
            return Result.Failure("Flight not found", "not_found");

        try
        {
            flight.Cancel(request.Reason);
        }
        catch (DomainException ex)
        {
            return Result.Failure(ex.Message, "domain_error");
        }

        _repository.Update(flight);

        await _publisher.PublishAsync(new FlightCancelledIntegrationEvent
        {
            FlightId = flight.Id,
            FlightNumber = flight.FlightNumber.Value,
            Reason = request.Reason
        }, ct);

        await _unitOfWork.SaveChangesAsync(ct);

        _logger.LogInformation("Cancelled flight {FlightId}: {Reason}", flight.Id, request.Reason);

        return Result.Success();
    }
}
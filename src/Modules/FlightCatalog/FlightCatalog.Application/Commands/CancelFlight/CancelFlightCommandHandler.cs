using FlightCatalog.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;

namespace FlightCatalog.Application.Commands.CancelFlight;

public sealed class CancelFlightCommandHandler : IRequestHandler<CancelFlightCommand, Result>
{
    private readonly IFlightRepository _repository;
    private readonly IUnitOfWork _unitOfWork;

    public CancelFlightCommandHandler(IFlightRepository repository, IUnitOfWork unitOfWork)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
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
        await _unitOfWork.SaveChangesAsync(ct);
        return Result.Success();
    }
}
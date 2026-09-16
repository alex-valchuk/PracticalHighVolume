using Bookings.Application.Abstractions;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.AddTicket;

public sealed class AddTicketCommandHandler : IRequestHandler<AddTicketCommand, Result<Guid>>
{
    // FlightStatus values from FlightCatalog.Domain.
    private const int FlightStatusScheduled = 0;
    private const int FlightStatusDelayed = 1;

    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IFlightCatalogClient _flightCatalog;
    private readonly ILogger<AddTicketCommandHandler> _logger;

    public AddTicketCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        IFlightCatalogClient flightCatalog,
        ILogger<AddTicketCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _flightCatalog = flightCatalog;
        _logger = logger;
    }

    public async Task<Result<Guid>> Handle(AddTicketCommand request, CancellationToken ct)
    {
        var booking = await _repository.GetByIdAsync(request.BookingId, ct);
        if (booking is null)
            return Result<Guid>.Failure("Booking not found.", "not_found");

        var flight = await _flightCatalog.GetFlightAsync(request.FlightId, ct);
        if (flight is null)
            return Result<Guid>.Failure("Flight not found.", "flight_not_found");

        if (flight.Status != FlightStatusScheduled && flight.Status != FlightStatusDelayed)
        {
            _logger.LogWarning(
                "Attempted to add ticket for flight {FlightId} with status {Status}",
                request.FlightId, flight.Status);
            return Result<Guid>.Failure(
                "Flight is not available for booking.", "flight_unavailable");
        }

        try
        {
            var ticketId = booking.AddTicket(
                PassengerId.Create(request.PassengerId),
                PassengerName.Create(request.PassengerName),
                request.FlightId,
                request.Amount);

            // NO Update() call: the entity is already tracked by EF Core.
            // EF Core detects the added Ticket in the owned collection and
            // issues INSERT automatically.
            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation(
                "Added ticket {TicketId} to booking {BookingId} for flight {FlightId}",
                ticketId, booking.Id, request.FlightId);

            return Result<Guid>.Success(ticketId);
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "Domain rule violated while adding ticket");
            return Result<Guid>.Failure(ex.Message, "domain_error");
        }
    }
}
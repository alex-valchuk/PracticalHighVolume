using Bookings.Application.Abstractions;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.AddTicket;

public sealed class AddTicketCommandHandler : IRequestHandler<AddTicketCommand, Result<Guid>>
{
    private const int FlightStatusScheduled = 0;
    private const int FlightStatusDelayed = 1;
    private static readonly TimeSpan LockTtl = TimeSpan.FromSeconds(10);

    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IFlightCatalogClient _flightCatalog;
    private readonly IDistributedLockService _lockService;
    private readonly ILogger<AddTicketCommandHandler> _logger;

    public AddTicketCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        IFlightCatalogClient flightCatalog,
        IDistributedLockService lockService,
        ILogger<AddTicketCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _flightCatalog = flightCatalog;
        _lockService = lockService;
        _logger = logger;
    }

    public async Task<Result<Guid>> Handle(AddTicketCommand request, CancellationToken ct)
    {
        // Serialize concurrent mutations of the same booking aggregate.
        var lockKey = CacheKeys.BookingLock(request.BookingId);
        await using var lockHandle = await _lockService.TryAcquireAsync(lockKey, LockTtl, ct);

        if (lockHandle is null)
        {
            _logger.LogWarning(
                "Concurrent modification detected for booking {BookingId}",
                request.BookingId);
            return Result<Guid>.Failure(
                "Another operation is in progress on this booking. Retry.",
                "concurrent_modification");
        }

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
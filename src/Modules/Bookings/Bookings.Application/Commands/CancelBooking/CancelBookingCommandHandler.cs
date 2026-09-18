using Bookings.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.CancelBooking;

public sealed class CancelBookingCommandHandler : IRequestHandler<CancelBookingCommand, Result>
{
    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ISeatReservationService _seatReservations;
    private readonly IIntegrationEventPublisher _publisher;
    private readonly ILogger<CancelBookingCommandHandler> _logger;

    public CancelBookingCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        ISeatReservationService seatReservations,
        IIntegrationEventPublisher publisher,
        ILogger<CancelBookingCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _seatReservations = seatReservations;
        _publisher = publisher;
        _logger = logger;
    }

    public async Task<Result> Handle(CancelBookingCommand request, CancellationToken ct)
    {
        var booking = await _repository.GetByIdAsync(request.BookingId, ct);
        if (booking is null)
            return Result.Failure("Booking not found.", "not_found");

        try
        {
            booking.Cancel(request.Reason);
        }
        catch (DomainException ex)
        {
            return Result.Failure(ex.Message, "domain_error");
        }

        await _seatReservations.ReleaseAllForBookingAsync(booking.Id, ct);

        await _publisher.PublishAsync(new BookingCancelledIntegrationEvent
        {
            BookingId = booking.Id,
            BookingReference = booking.BookRef.Value,
            Reason = request.Reason
        }, ct);

        await _unitOfWork.SaveChangesAsync(ct);

        _logger.LogInformation("Booking {BookingId} cancelled: {Reason}", booking.Id, request.Reason);

        return Result.Success();
    }
}
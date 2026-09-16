using Bookings.Application.Abstractions;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.ConfirmBooking;

/// <summary>
/// Orchestration saga for confirming a booking.
///
/// Steps:
///   1. Verify each flight is available.
///   2. Reserve a seat for each ticket.
///   3. Charge payment.
///   4. Mark booking Confirmed.
///
/// Compensations (in reverse order) on any failure after step 2 begins:
///   - Refund payment if charged.
///   - Release all seat reservations.
///   - Mark booking Expired.
///
/// Compensations are idempotent and individually fault-tolerant: a failing
/// compensation is logged and does not abort the rest.
/// </summary>
public sealed class ConfirmBookingCommandHandler
    : IRequestHandler<ConfirmBookingCommand, Result<ConfirmBookingResult>>
{
    private const int FlightStatusScheduled = 0;
    private const int FlightStatusDelayed = 1;

    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IFlightCatalogClient _flightCatalog;
    private readonly ISeatReservationService _seatReservations;
    private readonly IPaymentGateway _paymentGateway;
    private readonly ILogger<ConfirmBookingCommandHandler> _logger;

    public ConfirmBookingCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        IFlightCatalogClient flightCatalog,
        ISeatReservationService seatReservations,
        IPaymentGateway paymentGateway,
        ILogger<ConfirmBookingCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _flightCatalog = flightCatalog;
        _seatReservations = seatReservations;
        _paymentGateway = paymentGateway;
        _logger = logger;
    }

    public async Task<Result<ConfirmBookingResult>> Handle(ConfirmBookingCommand request, CancellationToken ct)
    {
        var booking = await _repository.GetByIdAsync(request.BookingId, ct);
        if (booking is null)
            return Result<ConfirmBookingResult>.Failure("Booking not found.", "not_found");

        if (booking.Status == BookingStatus.Confirmed)
        {
            _logger.LogInformation("Booking {BookingId} is already Confirmed - idempotent return", booking.Id);
            return Result<ConfirmBookingResult>.Success(
                new ConfirmBookingResult(booking.Id, true, null));
        }

        if (booking.Status != BookingStatus.Pending)
            return Result<ConfirmBookingResult>.Failure(
                "Booking in status " + booking.Status + " cannot be confirmed.", "invalid_status");

        if (booking.Tickets.Count == 0)
            return Result<ConfirmBookingResult>.Failure("Booking has no tickets.", "no_tickets");

        var reservedIds = new List<Guid>();
        Guid? paymentId = null;

        try
        {
            // Step 1+2: verify flights + reserve seats
            foreach (var ticket in booking.Tickets)
            {
                var flight = await _flightCatalog.GetFlightAsync(ticket.FlightId, ct);
                if (flight is null)
                    throw new SagaFailureException("Flight " + ticket.FlightId + " not found.");

                if (flight.Status != FlightStatusScheduled && flight.Status != FlightStatusDelayed)
                    throw new SagaFailureException("Flight " + ticket.FlightId + " is not available.");

                var reservationId = await _seatReservations.ReserveAsync(
                    booking.Id, ticket.Id, ticket.FlightId, ct);
                reservedIds.Add(reservationId);

                _logger.LogInformation(
                    "Saga step: reserved seat {ReservationId} for ticket {TicketId} on flight {FlightId}",
                    reservationId, ticket.Id, ticket.FlightId);
            }

            // Step 3: charge payment
            var paymentResult = await _paymentGateway.ChargeAsync(
                booking.Id, booking.TotalAmount.Amount, booking.TotalAmount.Currency, ct);

            if (!paymentResult.Success)
                throw new SagaFailureException(paymentResult.FailureReason ?? "Payment failed.");

            paymentId = paymentResult.PaymentId;
            _logger.LogInformation(
                "Saga step: charged payment {PaymentId} for booking {BookingId} amount {Amount} {Currency}",
                paymentId, booking.Id, booking.TotalAmount.Amount, booking.TotalAmount.Currency);

            // Demo/testing hook: simulate a failure AFTER the charge succeeded,
            // so that compensation (refund + release + expire) is exercised.
            // Always false in production (PaymentOptions.SimulateFailureAfterCharge = false).
            if (paymentResult.SimulateFailureAfterCharge)
                throw new SagaFailureException("Simulated failure after charge (demo).");

            // Step 4: confirm
            booking.Confirm();
            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation("Saga completed: booking {BookingId} confirmed", booking.Id);

            return Result<ConfirmBookingResult>.Success(
                new ConfirmBookingResult(booking.Id, true, null));
        }
        catch (SagaFailureException ex)
        {
            _logger.LogWarning("Saga failed for booking {BookingId}: {Reason}", booking.Id, ex.Message);
            await CompensateAsync(booking, reservedIds, paymentId, ex.Message, ct);
            return Result<ConfirmBookingResult>.Failure(ex.Message, "saga_failed");
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "Domain rule violated during confirmation of booking {BookingId}", booking.Id);
            await CompensateAsync(booking, reservedIds, paymentId, ex.Message, ct);
            return Result<ConfirmBookingResult>.Failure(ex.Message, "domain_error");
        }
        catch (OperationCanceledException)
        {
            // Do not compensate on cancellation - the caller is going away.
            throw;
        }
        catch (Exception ex)
        {
            // Catch-all: any unexpected error after the saga started must still
            // trigger compensation, otherwise money is charged with no booking.
            _logger.LogError(ex,
                "Unexpected error during saga for booking {BookingId} - running compensation",
                booking.Id);
            await CompensateAsync(booking, reservedIds, paymentId,
                "Unexpected error: " + ex.Message, ct);
            return Result<ConfirmBookingResult>.Failure(ex.Message, "saga_error");
        }
    }

    private async Task CompensateAsync(
        Booking booking,
        List<Guid> reservedIds,
        Guid? paymentId,
        string reason,
        CancellationToken ct)
    {
        _logger.LogWarning(
            "Saga compensation started for booking {BookingId}: reservations={Count}, payment={PaymentId}",
            booking.Id, reservedIds.Count, paymentId?.ToString() ?? "none");

        // Compensation step 1: refund payment (if charged)
        if (paymentId.HasValue)
        {
            try
            {
                await _paymentGateway.RefundAsync(paymentId.Value, ct);
                _logger.LogInformation(
                    "Saga compensation: refunded payment {PaymentId}", paymentId.Value);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Saga compensation: refund failed for payment {PaymentId}", paymentId.Value);
            }
        }

        // Compensation step 2: release all seat reservations
        foreach (var id in reservedIds)
        {
            try
            {
                await _seatReservations.ReleaseAsync(id, ct);
                _logger.LogInformation("Saga compensation: released reservation {ReservationId}", id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Saga compensation: release failed for reservation {ReservationId}", id);
            }
        }

        // Compensation step 3: mark booking Expired.
        // Use ExpireForCompensation (not MarkExpired) because the in-memory
        // status may already be Confirmed if the final SaveChanges failed.
        try
        {
            booking.ExpireForCompensation(reason);
            await _unitOfWork.SaveChangesAsync(ct);
            _logger.LogInformation("Saga compensation: booking {BookingId} marked Expired", booking.Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Saga compensation: failed to expire booking {BookingId}", booking.Id);
        }

        _logger.LogInformation("Saga compensation finished for booking {BookingId}", booking.Id);
    }

    private sealed class SagaFailureException : Exception
    {
        public SagaFailureException(string message) : base(message) { }
    }
}
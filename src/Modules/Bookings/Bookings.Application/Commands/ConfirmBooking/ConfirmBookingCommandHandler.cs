using System.Diagnostics;
using Bookings.Application.Abstractions;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.Observability;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.ConfirmBooking;

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
    private readonly IIntegrationEventPublisher _publisher;
    private readonly ILogger<ConfirmBookingCommandHandler> _logger;

    public ConfirmBookingCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        IFlightCatalogClient flightCatalog,
        ISeatReservationService seatReservations,
        IPaymentGateway paymentGateway,
        IIntegrationEventPublisher publisher,
        ILogger<ConfirmBookingCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _flightCatalog = flightCatalog;
        _seatReservations = seatReservations;
        _paymentGateway = paymentGateway;
        _publisher = publisher;
        _logger = logger;
    }

    public async Task<Result<ConfirmBookingResult>> Handle(ConfirmBookingCommand request, CancellationToken ct)
    {
        using var sagaActivity = ActivitySources.Saga.Instance.StartActivity(
            "saga.confirm_booking",
            ActivityKind.Internal);

        sagaActivity?.SetTag("booking.id", request.BookingId);

        var sw = Stopwatch.StartNew();
        var outcome = "unknown";

        try
        {
            var result = await ExecuteAsync(request, ct);
            outcome = result.IsSuccess ? "success" : "failure";
            sagaActivity?.SetTag("saga.outcome", outcome);
            return result;
        }
        catch
        {
            outcome = "error";
            sagaActivity?.SetTag("saga.outcome", outcome);
            throw;
        }
        finally
        {
            sw.Stop();
            Meters.SagaDuration.Record(sw.Elapsed.TotalMilliseconds,
                new KeyValuePair<string, object?>("outcome", outcome));
        }
    }

    private async Task<Result<ConfirmBookingResult>> ExecuteAsync(ConfirmBookingCommand request, CancellationToken ct)
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
            using (var step = ActivitySources.Saga.Instance.StartActivity("saga.step.verify_and_reserve"))
            {
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
                }

                step?.SetTag("seats.reserved", reservedIds.Count);
            }

            using (var step = ActivitySources.Saga.Instance.StartActivity("saga.step.charge_payment"))
            {
                var paymentResult = await _paymentGateway.ChargeAsync(
                    booking.Id, booking.TotalAmount.Amount, booking.TotalAmount.Currency, ct);

                if (!paymentResult.Success)
                    throw new SagaFailureException(paymentResult.FailureReason ?? "Payment failed.");

                paymentId = paymentResult.PaymentId;
                step?.SetTag("payment.id", paymentId?.ToString());
                step?.SetTag("payment.amount", booking.TotalAmount.Amount);

                if (paymentResult.SimulateFailureAfterCharge)
                    throw new SagaFailureException("Simulated failure after charge (demo).");
            }

            using (var step = ActivitySources.Saga.Instance.StartActivity("saga.step.confirm"))
            {
                booking.Confirm();

                await _publisher.PublishAsync(new BookingConfirmedIntegrationEvent
                {
                    BookingId = booking.Id,
                    BookingReference = booking.BookRef.Value,
                    PassengerId = booking.PassengerId.Value,
                    PassengerName = booking.PassengerName.Value,
                    TotalAmount = booking.TotalAmount.Amount,
                    Currency = booking.TotalAmount.Currency,
                    TicketCount = booking.Tickets.Count
                }, ct);

                await _unitOfWork.SaveChangesAsync(ct);
                step?.SetTag("booking.status", booking.Status.ToString());
            }

            Meters.BookingsConfirmed.Add(1);

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
            throw;
        }
        catch (Exception ex)
        {
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
        using var compensationActivity = ActivitySources.Saga.Instance.StartActivity(
            "saga.compensation",
            ActivityKind.Internal);
        compensationActivity?.SetTag("compensation.reason", reason);

        _logger.LogWarning(
            "Saga compensation started for booking {BookingId}: reservations={Count}, payment={PaymentId}",
            booking.Id, reservedIds.Count, paymentId?.ToString() ?? "none");

        if (paymentId.HasValue)
        {
            using var refundStep = ActivitySources.Saga.Instance.StartActivity("saga.compensation.refund");
            try
            {
                await _paymentGateway.RefundAsync(paymentId.Value, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Saga compensation: refund failed for payment {PaymentId}", paymentId.Value);
                refundStep?.SetStatus(ActivityStatusCode.Error, ex.Message);
            }
        }

        if (reservedIds.Count > 0)
        {
            using var releaseStep = ActivitySources.Saga.Instance.StartActivity("saga.compensation.release_seats");
            foreach (var id in reservedIds)
            {
                try
                {
                    await _seatReservations.ReleaseAsync(id, ct);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Saga compensation: release failed for reservation {ReservationId}", id);
                }
            }
        }

        try
        {
            booking.ExpireForCompensation(reason);

            await _publisher.PublishAsync(new BookingExpiredIntegrationEvent
            {
                BookingId = booking.Id,
                BookingReference = booking.BookRef.Value,
                Reason = reason
            }, ct);

            await _unitOfWork.SaveChangesAsync(ct);

            Meters.BookingsExpired.Add(1);
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
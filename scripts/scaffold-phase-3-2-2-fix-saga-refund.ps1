#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-File {
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [string] $Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $full = Join-Path (Get-Location).Path $Path
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path)
}

Write-Host ""
Write-Host "=== Fix: refund path in saga + catch-all + demo hook ==="
Write-Host ""

$bd  = "src/Modules/Bookings/Bookings.Domain"
$ba  = "src/Modules/Bookings/Bookings.Application"
$bi  = "src/Modules/Bookings/Bookings.Infrastructure"
$hostDir = "src/Hosts/FlightsPlatform.Api"
$tests = "tests/Bookings.UnitTests"

# ===========================================================================
# 1. PaymentResult: add SimulateFailureAfterCharge flag
# ===========================================================================
Write-Host "=== 1. IPaymentGateway contract ==="

Write-File "$ba/Abstractions/IPaymentGateway.cs" @'
namespace Bookings.Application.Abstractions;

public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(Guid bookingId, decimal amount, string currency, CancellationToken ct = default);
    Task RefundAsync(Guid paymentId, CancellationToken ct = default);
}

/// <summary>
/// Result of a charge attempt.
/// SimulateFailureAfterCharge is a demo/testing flag: when true, the saga
/// handler treats the charge as successful (paymentId is set) but then
/// throws internally right after it, so that the compensation path
/// (refund + release + expire) can be exercised end-to-end.
/// In production this flag is always false.
/// </summary>
public sealed record PaymentResult(
    bool Success,
    Guid? PaymentId,
    string? FailureReason,
    bool SimulateFailureAfterCharge = false);
'@

# ===========================================================================
# 2. PaymentOptions: add SimulateFailureAfterCharge
# ===========================================================================
Write-Host ""
Write-Host "=== 2. PaymentOptions ==="

Write-File "$bi/Options/PaymentOptions.cs" @'
namespace Bookings.Infrastructure.Options;

public sealed class PaymentOptions
{
    public const string SectionName = "Payment";

    /// <summary>0-100. Percent of charge attempts that will be declined.</summary>
    public int FailureRatePercent { get; set; } = 20;

    public int MinDelayMs { get; set; } = 100;
    public int MaxDelayMs { get; set; } = 500;

    /// <summary>
    /// Demo/testing hook. When true, the charge succeeds (a Payment row is
    /// written with status Charged) and then the saga handler immediately
    /// throws, triggering compensation (refund + release seats + expire).
    /// Leave false in production.
    /// </summary>
    public bool SimulateFailureAfterCharge { get; set; } = false;
}
'@

# ===========================================================================
# 3. Booking: add ExpireForCompensation
# ===========================================================================
Write-Host ""
Write-Host "=== 3. Booking.ExpireForCompensation ==="

Write-File "$bd/Aggregates/Booking.cs" @'
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class Booking : AggregateRoot<Guid>
{
    private readonly List<Ticket> _tickets = new();

    public BookingReference BookRef { get; private set; } = default!;
    public DateTimeOffset BookDate { get; private set; }
    public Money TotalAmount { get; private set; } = default!;
    public BookingStatus Status { get; private set; }
    public PassengerId PassengerId { get; private set; } = default!;
    public PassengerName PassengerName { get; private set; } = default!;

    public IReadOnlyCollection<Ticket> Tickets => _tickets.AsReadOnly();

    private Booking() { }

    private Booking(
        Guid id,
        BookingReference bookRef,
        DateTimeOffset bookDate,
        Money totalAmount,
        PassengerId passengerId,
        PassengerName passengerName) : base(id)
    {
        BookRef = bookRef;
        BookDate = bookDate;
        TotalAmount = totalAmount;
        Status = BookingStatus.Pending;
        PassengerId = passengerId;
        PassengerName = passengerName;
    }

    public static Booking CreateDraft(
        PassengerId passengerId,
        PassengerName passengerName,
        string currency)
    {
        var booking = new Booking(
            Guid.NewGuid(),
            BookingReference.Generate(),
            DateTimeOffset.UtcNow,
            Money.Zero(currency),
            passengerId,
            passengerName);

        booking.Raise(new BookingCreated(
            booking.Id,
            booking.BookRef.Value,
            passengerId.Value,
            currency.ToUpperInvariant()));

        return booking;
    }

    public Guid AddTicket(
        PassengerId passengerId,
        PassengerName passengerName,
        Guid flightId,
        decimal amount)
    {
        if (Status != BookingStatus.Pending)
            throw new DomainException(
                "Cannot add a ticket to a booking that is not Pending. Current status: " + Status);

        if (flightId == Guid.Empty)
            throw new DomainException("FlightId is required.");

        if (amount <= 0)
            throw new DomainException("Ticket amount must be positive.");

        var duplicate = _tickets.Any(t =>
            t.FlightId == flightId && t.PassengerId == passengerId);

        if (duplicate)
            throw new DomainException(
                "Passenger " + passengerId.Value + " is already on flight " + flightId);

        var ticketNo = Guid.NewGuid().ToString("N").Substring(0, 13);
        var ticket = new Ticket(
            Guid.NewGuid(),
            ticketNo,
            passengerId,
            passengerName,
            flightId,
            amount);

        _tickets.Add(ticket);

        TotalAmount = TotalAmount.Add(Money.Create(amount, TotalAmount.Currency));

        Raise(new TicketAdded(
            Id,
            ticket.Id,
            flightId,
            amount,
            TotalAmount.Currency));

        return ticket.Id;
    }

    public void Confirm()
    {
        if (Status == BookingStatus.Confirmed)
            throw new DomainException("Booking is already confirmed.");

        if (Status != BookingStatus.Pending)
            throw new DomainException(
                "Cannot confirm a booking in status " + Status + ".");

        if (_tickets.Count == 0)
            throw new DomainException("Cannot confirm a booking without tickets.");

        Status = BookingStatus.Confirmed;

        Raise(new BookingConfirmed(
            Id,
            BookRef.Value,
            TotalAmount.Amount,
            TotalAmount.Currency));
    }

    public void MarkExpired(string reason)
    {
        if (Status != BookingStatus.Pending)
            throw new DomainException(
                "Cannot expire a booking in status " + Status + ".");

        if (string.IsNullOrWhiteSpace(reason))
            throw new DomainException("Expiration reason is required.");

        Status = BookingStatus.Expired;

        Raise(new BookingExpired(Id, BookRef.Value, reason));
    }

    /// <summary>
    /// Saga compensation only. Transitions to Expired from any non-terminal
    /// state (Pending or Confirmed). This is required because the saga may
    /// call Confirm() in memory and then fail to persist - in that case the
    /// in-memory Status is already Confirmed but the DB still says Pending.
    /// Idempotent: does nothing if already Expired or Cancelled.
    /// </summary>
    public void ExpireForCompensation(string reason)
    {
        if (Status == BookingStatus.Expired || Status == BookingStatus.Cancelled)
            return;

        if (string.IsNullOrWhiteSpace(reason))
            reason = "Saga compensation";

        Status = BookingStatus.Expired;
        Raise(new BookingExpired(Id, BookRef.Value, reason));
    }

    public void Cancel(string reason)
    {
        if (Status == BookingStatus.Cancelled)
            throw new DomainException("Booking is already cancelled.");

        if (Status == BookingStatus.Confirmed)
            throw new DomainException("Cannot cancel a confirmed booking. Use refund flow.");

        if (string.IsNullOrWhiteSpace(reason))
            throw new DomainException("Cancellation reason is required.");

        Status = BookingStatus.Cancelled;
        Raise(new BookingCancelled(Id, BookRef.Value, reason));
    }
}
'@

# ===========================================================================
# 4. FakePaymentGateway: pass SimulateFailureAfterCharge from options
# ===========================================================================
Write-Host ""
Write-Host "=== 4. FakePaymentGateway ==="

Write-File "$bi/Integration/Payments/FakePaymentGateway.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.Persistence;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Bookings.Infrastructure.Integration.Payments;

/// <summary>
/// Deterministic fake payment gateway. Behaviour is driven by PaymentOptions.
/// Persists every attempt (charged or failed) to booking.payments so that
/// compensation and audits have durable records.
/// </summary>
internal sealed class FakePaymentGateway : IPaymentGateway
{
    private readonly BookingDbContext _db;
    private readonly PaymentOptions _options;
    private readonly ILogger<FakePaymentGateway> _logger;

    private static readonly Random Rng = new();

    public FakePaymentGateway(
        BookingDbContext db,
        IOptions<PaymentOptions> options,
        ILogger<FakePaymentGateway> logger)
    {
        _db = db;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<PaymentResult> ChargeAsync(
        Guid bookingId, decimal amount, string currency, CancellationToken ct = default)
    {
        var delay = _options.MaxDelayMs > _options.MinDelayMs
            ? Rng.Next(_options.MinDelayMs, _options.MaxDelayMs + 1)
            : Math.Max(0, _options.MinDelayMs);

        if (delay > 0)
            await Task.Delay(delay, ct);

        var failRate = Math.Clamp(_options.FailureRatePercent, 0, 100);
        var shouldFail = Rng.Next(100) < failRate;

        if (shouldFail)
        {
            var failed = Domain.Aggregates.Payment.CreateFailed(bookingId, amount, currency);
            _db.Payments.Add(failed);
            await _db.SaveChangesAsync(ct);

            _logger.LogWarning(
                "FakePaymentGateway DECLINED charge: booking={BookingId} amount={Amount} {Currency}",
                bookingId, amount, currency);

            return new PaymentResult(false, null, "Card declined (fake).");
        }

        var reference = "FAKE-" + Guid.NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant();
        var payment = Domain.Aggregates.Payment.CreateCharged(bookingId, amount, currency, reference);
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "FakePaymentGateway CHARGED: booking={BookingId} amount={Amount} {Currency} payment={PaymentId} ref={Ref}",
            bookingId, amount, currency, payment.Id, reference);

        return new PaymentResult(true, payment.Id, null, _options.SimulateFailureAfterCharge);
    }

    public async Task RefundAsync(Guid paymentId, CancellationToken ct = default)
    {
        var payment = await _db.Payments.FindAsync(new object[] { paymentId }, ct);
        if (payment is null)
        {
            _logger.LogWarning("FakePaymentGateway REFUND skipped - payment {PaymentId} not found", paymentId);
            return;
        }

        payment.MarkRefunded();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("FakePaymentGateway REFUNDED: payment={PaymentId}", paymentId);
    }
}
'@

# ===========================================================================
# 5. ConfirmBookingCommandHandler: catch-all + demo hook + ExpireForCompensation
# ===========================================================================
Write-Host ""
Write-Host "=== 5. ConfirmBookingCommandHandler ==="

Write-File "$ba/Commands/ConfirmBooking/ConfirmBookingCommandHandler.cs" @'
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
'@

# ===========================================================================
# 6. Add test for refund path
# ===========================================================================
Write-Host ""
Write-Host "=== 6. New test: refund path ==="

Write-File "$tests/Application/ConfirmBookingCommandHandlerTests.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.Commands.ConfirmBooking;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class ConfirmBookingCommandHandlerTests
{
    private const int StatusScheduled = 0;
    private const int StatusCancelled = 4;

    private static Booking MakeBookingWithTicket(out Guid flightId)
    {
        var booking = Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

        flightId = Guid.NewGuid();
        booking.AddTicket(
            PassengerId.Create("9999999999"),
            PassengerName.Create("PETROV PETR"),
            flightId,
            12000m);

        return booking;
    }

    private static FlightSummary Summary(Guid id, int status = StatusScheduled)
        => new(id, "PG-0001", "SVO", "OVB",
               DateTimeOffset.UtcNow.AddDays(1),
               DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
               status);

    private static ConfirmBookingCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<IFlightCatalogClient> fc,
        Mock<ISeatReservationService> seats,
        Mock<IPaymentGateway> pay)
        => new(repo.Object, uow.Object, fc.Object, seats.Object, pay.Object,
               NullLogger<ConfirmBookingCommandHandler>.Instance);

    private static void SetupBooking(Mock<IBookingRepository> repo, Booking b)
    {
        repo.Setup(r => r.GetByIdAsync(b.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(b);
    }

    [Fact]
    public async Task Handle_HappyPath_ConfirmsBooking()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Guid.NewGuid());

        var paymentId = Guid.NewGuid();
        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(true, paymentId, null));

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Confirmed.Should().BeTrue();
        booking.Status.Should().Be(BookingStatus.Confirmed);

        seats.Verify(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()), Times.Once);
        pay.Verify(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()), Times.Once);
        seats.Verify(s => s.ReleaseAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
        pay.Verify(p => p.RefundAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_AlreadyConfirmed_IsIdempotent()
    {
        var booking = MakeBookingWithTicket(out _);
        booking.Confirm();

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var seats = new Mock<ISeatReservationService>();
        var pay = new Mock<IPaymentGateway>();

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<IFlightCatalogClient>(), seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Confirmed.Should().BeTrue();

        seats.Verify(s => s.ReserveAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
        pay.Verify(p => p.ChargeAsync(It.IsAny<Guid>(), It.IsAny<decimal>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_NoTickets_ReturnsFailure()
    {
        var booking = Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var handler = Build(repo, new Mock<IUnitOfWork>(),
            new Mock<IFlightCatalogClient>(),
            new Mock<ISeatReservationService>(),
            new Mock<IPaymentGateway>());

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("no_tickets");
    }

    [Fact]
    public async Task Handle_FlightCancelled_TriggersCompensation()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId, StatusCancelled));

        var seats = new Mock<ISeatReservationService>();
        var pay = new Mock<IPaymentGateway>();

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_failed");
        booking.Status.Should().Be(BookingStatus.Expired);

        pay.Verify(p => p.ChargeAsync(It.IsAny<Guid>(), It.IsAny<decimal>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
        seats.Verify(s => s.ReleaseAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_PaymentDeclined_ReleasesSeatsAndExpires()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var reservationId = Guid.NewGuid();
        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(reservationId);

        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(false, null, "Card declined (fake)."));

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_failed");
        booking.Status.Should().Be(BookingStatus.Expired);

        seats.Verify(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()), Times.Once);
        pay.Verify(p => p.RefundAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_BookingNotFound_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Booking?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(),
            new Mock<IFlightCatalogClient>(),
            new Mock<ISeatReservationService>(),
            new Mock<IPaymentGateway>());

        var result = await handler.Handle(new ConfirmBookingCommand(Guid.NewGuid()), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    // ---------------------------------------------------------------------
    // NEW: refund path - charge succeeded, then something after it failed.
    // Two scenarios covered:
    //   1. Explicit demo hook (SimulateFailureAfterCharge = true)
    //   2. Unexpected exception (e.g. DbUpdateException from SaveChanges)
    // ---------------------------------------------------------------------

    [Fact]
    public async Task Handle_SimulateFailureAfterCharge_RefundsAndReleases()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var reservationId = Guid.NewGuid();
        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(reservationId);
        seats.Setup(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var paymentId = Guid.NewGuid();
        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(true, paymentId, null, SimulateFailureAfterCharge: true));
        pay.Setup(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_failed");
        booking.Status.Should().Be(BookingStatus.Expired);

        pay.Verify(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()), Times.Once);
        seats.Verify(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_UnexpectedExceptionAfterCharge_RefundsAndReleases()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        // First SaveChanges (post-Confirm) throws; second (during compensation) succeeds.
        var uow = new Mock<IUnitOfWork>();
        uow.SetupSequence(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Simulated DB failure"))
            .ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var reservationId = Guid.NewGuid();
        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(reservationId);
        seats.Setup(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var paymentId = Guid.NewGuid();
        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(true, paymentId, null));
        pay.Setup(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_error");
        booking.Status.Should().Be(BookingStatus.Expired);

        pay.Verify(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()), Times.Once);
        seats.Verify(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()), Times.Once);
    }
}
'@

# ===========================================================================
# 7. appsettings.json - document demo config
# ===========================================================================
Write-Host ""
Write-Host "=== 7. appsettings.json ==="

Write-File "$hostDir/appsettings.json" @'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "ConnectionStrings": {
    "FlightCatalog": "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password",
    "Booking": "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password",
    "BookingsSource": "Host=127.0.0.1;Port=5433;Database=demo;Username=flights;Password=flights_dev_password;ApplicationName=FlightsPlatform.Sync"
  },
  "AirportSync": {
    "Enabled": true,
    "IntervalMinutes": 15,
    "SyncOnStartup": true
  },
  "Payment": {
    "FailureRatePercent": 20,
    "MinDelayMs": 100,
    "MaxDelayMs": 500,
    "SimulateFailureAfterCharge": false
  },
  "AllowedHosts": "*"
}
'@

# ===========================================================================
# Build + test
# ===========================================================================
Write-Host ""
Write-Host "=== Clean + build ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED - see errors above." -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

Write-Host ""
Write-Host "=== dotnet test ==="
dotnet test --no-build --nologo

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "How to demo the REFUND path via API:" -ForegroundColor Yellow
Write-Host "  1. In appsettings.json set:"
Write-Host '       "Payment": { "FailureRatePercent": 0, "SimulateFailureAfterCharge": true }'
Write-Host "  2. dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  3. Create booking, add ticket, POST /bookings/{id}/confirm"
Write-Host "  4. Expected: 400 saga_failed. Logs show CHARGED -> Simulated failure -> REFUNDED -> released reservation -> Expired"
Write-Host "  5. In DB: booking.payments has one row (status=Refunded), seat_reservations status=Released, booking.status=Expired"
Write-Host "  6. Reset back to SimulateFailureAfterCharge=false"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(bookings): refund path in saga + catch-all compensation + demo hook"'
Write-Host "  git push"
Write-Host ""
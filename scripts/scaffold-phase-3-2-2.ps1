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
Write-Host "=== SPEC-003.2 - Script 3.2.2 ==="
Write-Host "Saga: ConfirmBooking + CancelBooking + Payment + SeatReservation"
Write-Host ""

$bd = "src/Modules/Bookings/Bookings.Domain"
$ba = "src/Modules/Bookings/Bookings.Application"
$bi = "src/Modules/Bookings/Bookings.Infrastructure"
$bp = "src/Modules/Bookings/Bookings.Api"
$hostDir = "src/Hosts/FlightsPlatform.Api"
$tests = "tests/Bookings.UnitTests"

# ===========================================================================
# T-09: SeatReservation entity
# ===========================================================================
Write-Host "=== T-09. SeatReservation entity ==="

Write-File "$bd/SeatReservationStatus.cs" @'
namespace Bookings.Domain;

public enum SeatReservationStatus
{
    Active = 0,
    Released = 1
}
'@

Write-File "$bd/Aggregates/SeatReservation.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class SeatReservation : Entity<Guid>
{
    public Guid BookingId { get; private set; }
    public Guid TicketId { get; private set; }
    public Guid FlightId { get; private set; }
    public SeatReservationStatus Status { get; private set; }
    public DateTimeOffset ReservedAt { get; private set; }
    public DateTimeOffset? ReleasedAt { get; private set; }

    private SeatReservation() { }

    private SeatReservation(Guid id, Guid bookingId, Guid ticketId, Guid flightId) : base(id)
    {
        BookingId = bookingId;
        TicketId = ticketId;
        FlightId = flightId;
        Status = SeatReservationStatus.Active;
        ReservedAt = DateTimeOffset.UtcNow;
    }

    public static SeatReservation Create(Guid bookingId, Guid ticketId, Guid flightId)
    {
        if (bookingId == Guid.Empty) throw new DomainException("BookingId is required.");
        if (ticketId == Guid.Empty) throw new DomainException("TicketId is required.");
        if (flightId == Guid.Empty) throw new DomainException("FlightId is required.");

        return new SeatReservation(Guid.NewGuid(), bookingId, ticketId, flightId);
    }

    public void Release()
    {
        if (Status == SeatReservationStatus.Released) return;
        Status = SeatReservationStatus.Released;
        ReleasedAt = DateTimeOffset.UtcNow;
    }
}
'@

# ===========================================================================
# T-10: Payment entity
# ===========================================================================
Write-Host ""
Write-Host "=== T-10. Payment entity ==="

Write-File "$bd/PaymentStatus.cs" @'
namespace Bookings.Domain;

public enum PaymentStatus
{
    Charged = 0,
    Refunded = 1,
    Failed = 2
}
'@

Write-File "$bd/Aggregates/Payment.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class Payment : Entity<Guid>
{
    public Guid BookingId { get; private set; }
    public decimal Amount { get; private set; }
    public string Currency { get; private set; } = default!;
    public PaymentStatus Status { get; private set; }
    public string? ExternalReference { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset? RefundedAt { get; private set; }

    private Payment() { }

    private Payment(Guid id, Guid bookingId, decimal amount, string currency, string? externalReference)
        : base(id)
    {
        BookingId = bookingId;
        Amount = amount;
        Currency = currency;
        ExternalReference = externalReference;
        CreatedAt = DateTimeOffset.UtcNow;
    }

    public static Payment CreateCharged(Guid bookingId, decimal amount, string currency, string? externalReference)
    {
        if (bookingId == Guid.Empty) throw new DomainException("BookingId is required.");
        if (amount <= 0) throw new DomainException("Payment amount must be positive.");
        if (string.IsNullOrWhiteSpace(currency)) throw new DomainException("Currency is required.");

        return new Payment(Guid.NewGuid(), bookingId, amount, currency.ToUpperInvariant(), externalReference)
        {
            Status = PaymentStatus.Charged
        };
    }

    public static Payment CreateFailed(Guid bookingId, decimal amount, string currency)
    {
        return new Payment(Guid.NewGuid(), bookingId, amount, currency.ToUpperInvariant(), null)
        {
            Status = PaymentStatus.Failed
        };
    }

    public void MarkRefunded()
    {
        if (Status == PaymentStatus.Refunded) return;
        if (Status != PaymentStatus.Charged)
            throw new DomainException("Only charged payments can be refunded.");

        Status = PaymentStatus.Refunded;
        RefundedAt = DateTimeOffset.UtcNow;
    }
}
'@

# ===========================================================================
# Application abstractions
# ===========================================================================
Write-Host ""
Write-Host "=== Application abstractions ==="

Write-File "$ba/Abstractions/IPaymentGateway.cs" @'
namespace Bookings.Application.Abstractions;

public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(Guid bookingId, decimal amount, string currency, CancellationToken ct = default);
    Task RefundAsync(Guid paymentId, CancellationToken ct = default);
}

public sealed record PaymentResult(bool Success, Guid? PaymentId, string? FailureReason);
'@

Write-File "$ba/Abstractions/ISeatReservationService.cs" @'
namespace Bookings.Application.Abstractions;

public interface ISeatReservationService
{
    Task<Guid> ReserveAsync(Guid bookingId, Guid ticketId, Guid flightId, CancellationToken ct = default);
    Task ReleaseAsync(Guid reservationId, CancellationToken ct = default);
    Task ReleaseAllForBookingAsync(Guid bookingId, CancellationToken ct = default);
}
'@

# ===========================================================================
# T-14: ConfirmBookingCommand (saga)
# ===========================================================================
Write-Host ""
Write-Host "=== T-14. ConfirmBookingCommand (saga) ==="

Write-File "$ba/Commands/ConfirmBooking/ConfirmBookingCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.ConfirmBooking;

public sealed record ConfirmBookingResult(Guid BookingId, bool Confirmed, string? FailureReason);

public sealed record ConfirmBookingCommand(Guid BookingId) : IRequest<Result<ConfirmBookingResult>>;
'@

Write-File "$ba/Commands/ConfirmBooking/ConfirmBookingCommandValidator.cs" @'
using FluentValidation;

namespace Bookings.Application.Commands.ConfirmBooking;

public sealed class ConfirmBookingCommandValidator : AbstractValidator<ConfirmBookingCommand>
{
    public ConfirmBookingCommandValidator()
    {
        RuleFor(x => x.BookingId).NotEmpty();
    }
}
'@

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
/// Steps:
///   1. Verify each flight is available.
///   2. Reserve a seat for each ticket.
///   3. Charge payment.
///   4. Mark booking Confirmed.
/// On failure at any step, previously completed steps are compensated:
///   - Refund payment (if charged).
///   - Release all seat reservations.
///   - Mark booking Expired.
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

        // Compensation step 3: mark booking Expired
        try
        {
            booking.MarkExpired(reason);
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
# T-15: CancelBookingCommand
# ===========================================================================
Write-Host ""
Write-Host "=== T-15. CancelBookingCommand ==="

Write-File "$ba/Commands/CancelBooking/CancelBookingCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.CancelBooking;

public sealed record CancelBookingCommand(Guid BookingId, string Reason) : IRequest<Result>;
'@

Write-File "$ba/Commands/CancelBooking/CancelBookingCommandValidator.cs" @'
using FluentValidation;

namespace Bookings.Application.Commands.CancelBooking;

public sealed class CancelBookingCommandValidator : AbstractValidator<CancelBookingCommand>
{
    public CancelBookingCommandValidator()
    {
        RuleFor(x => x.BookingId).NotEmpty();
        RuleFor(x => x.Reason).NotEmpty().MaximumLength(500);
    }
}
'@

Write-File "$ba/Commands/CancelBooking/CancelBookingCommandHandler.cs" @'
using Bookings.Application.Abstractions;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.CancelBooking;

public sealed class CancelBookingCommandHandler : IRequestHandler<CancelBookingCommand, Result>
{
    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ISeatReservationService _seatReservations;
    private readonly ILogger<CancelBookingCommandHandler> _logger;

    public CancelBookingCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        ISeatReservationService seatReservations,
        ILogger<CancelBookingCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _seatReservations = seatReservations;
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

        // Release any active seat reservations for this booking.
        await _seatReservations.ReleaseAllForBookingAsync(booking.Id, ct);

        await _unitOfWork.SaveChangesAsync(ct);

        _logger.LogInformation("Booking {BookingId} cancelled: {Reason}", booking.Id, request.Reason);

        return Result.Success();
    }
}
'@

# ===========================================================================
# Infrastructure: options, configurations, services
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure: options, configs, services ==="

Write-File "$bi/Options/PaymentOptions.cs" @'
namespace Bookings.Infrastructure.Options;

public sealed class PaymentOptions
{
    public const string SectionName = "Payment";

    /// <summary>0-100. Percent of charge attempts that will be declined.</summary>
    public int FailureRatePercent { get; set; } = 20;

    public int MinDelayMs { get; set; } = 100;
    public int MaxDelayMs { get; set; } = 500;
}
'@

Write-File "$bi/Persistence/Configurations/SeatReservationConfiguration.cs" @'
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Bookings.Infrastructure.Persistence.Configurations;

public sealed class SeatReservationConfiguration : IEntityTypeConfiguration<SeatReservation>
{
    public void Configure(EntityTypeBuilder<SeatReservation> builder)
    {
        builder.ToTable("seat_reservations");
        builder.HasKey(r => r.Id);
        builder.Property(r => r.Id).HasColumnName("id").ValueGeneratedNever();

        builder.Property(r => r.BookingId).HasColumnName("booking_id").IsRequired();
        builder.Property(r => r.TicketId).HasColumnName("ticket_id").IsRequired();
        builder.Property(r => r.FlightId).HasColumnName("flight_id").IsRequired();
        builder.Property(r => r.Status).HasColumnName("status").HasConversion<int>().IsRequired();
        builder.Property(r => r.ReservedAt).HasColumnName("reserved_at").IsRequired();
        builder.Property(r => r.ReleasedAt).HasColumnName("released_at");

        builder.HasIndex(r => new { r.BookingId, r.Status });
        builder.HasIndex(r => r.TicketId);
    }
}
'@

Write-File "$bi/Persistence/Configurations/PaymentConfiguration.cs" @'
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Bookings.Infrastructure.Persistence.Configurations;

public sealed class PaymentConfiguration : IEntityTypeConfiguration<Payment>
{
    public void Configure(EntityTypeBuilder<Payment> builder)
    {
        builder.ToTable("payments");
        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id).HasColumnName("id").ValueGeneratedNever();

        builder.Property(p => p.BookingId).HasColumnName("booking_id").IsRequired();
        builder.Property(p => p.Amount).HasColumnName("amount").HasPrecision(18, 2).IsRequired();
        builder.Property(p => p.Currency).HasColumnName("currency").HasMaxLength(3).IsRequired();
        builder.Property(p => p.Status).HasColumnName("status").HasConversion<int>().IsRequired();
        builder.Property(p => p.ExternalReference).HasColumnName("external_reference").HasMaxLength(64);
        builder.Property(p => p.CreatedAt).HasColumnName("created_at").IsRequired();
        builder.Property(p => p.RefundedAt).HasColumnName("refunded_at");

        builder.HasIndex(p => p.BookingId);
    }
}
'@

Write-File "$bi/Integration/Payment/FakePaymentGateway.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Domain.Aggregates;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.Persistence;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Bookings.Infrastructure.Integration.Payment;

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
            var failed = Payment.CreateFailed(bookingId, amount, currency);
            _db.Payments.Add(failed);
            await _db.SaveChangesAsync(ct);

            _logger.LogWarning(
                "FakePaymentGateway DECLINED charge: booking={BookingId} amount={Amount} {Currency}",
                bookingId, amount, currency);

            return new PaymentResult(false, null, "Card declined (fake).");
        }

        var reference = "FAKE-" + Guid.NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant();
        var payment = Payment.CreateCharged(bookingId, amount, currency, reference);
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "FakePaymentGateway CHARGED: booking={BookingId} amount={Amount} {Currency} payment={PaymentId} ref={Ref}",
            bookingId, amount, currency, payment.Id, reference);

        return new PaymentResult(true, payment.Id, null);
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

Write-File "$bi/Persistence/Services/SeatReservationService.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Bookings.Infrastructure.Persistence.Services;

internal sealed class SeatReservationService : ISeatReservationService
{
    private readonly BookingDbContext _db;
    private readonly ILogger<SeatReservationService> _logger;

    public SeatReservationService(BookingDbContext db, ILogger<SeatReservationService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<Guid> ReserveAsync(
        Guid bookingId, Guid ticketId, Guid flightId, CancellationToken ct = default)
    {
        var reservation = SeatReservation.Create(bookingId, ticketId, flightId);
        _db.Set<SeatReservation>().Add(reservation);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "SeatReservationService: reserved {ReservationId} for booking={BookingId} ticket={TicketId} flight={FlightId}",
            reservation.Id, bookingId, ticketId, flightId);

        return reservation.Id;
    }

    public async Task ReleaseAsync(Guid reservationId, CancellationToken ct = default)
    {
        var reservation = await _db.Set<SeatReservation>()
            .FirstOrDefaultAsync(r => r.Id == reservationId, ct);

        if (reservation is null)
        {
            _logger.LogWarning("SeatReservationService: reservation {ReservationId} not found", reservationId);
            return;
        }

        reservation.Release();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("SeatReservationService: released {ReservationId}", reservationId);
    }

    public async Task ReleaseAllForBookingAsync(Guid bookingId, CancellationToken ct = default)
    {
        var active = await _db.Set<SeatReservation>()
            .Where(r => r.BookingId == bookingId && r.Status == SeatReservationStatus.Active)
            .ToListAsync(ct);

        if (active.Count == 0) return;

        foreach (var r in active) r.Release();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "SeatReservationService: released {Count} reservations for booking={BookingId}",
            active.Count, bookingId);
    }
}
'@

# ===========================================================================
# DbContext update
# ===========================================================================
Write-Host ""
Write-Host "=== DbContext update ==="

Write-File "$bi/Persistence/BookingDbContext.cs" @'
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace Bookings.Infrastructure.Persistence;

public sealed class BookingDbContext : DbContext
{
    public const string SchemaName = "booking";

    public BookingDbContext(DbContextOptions<BookingDbContext> options)
        : base(options) { }

    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<SeatReservation> SeatReservations => Set<SeatReservation>();
    public DbSet<Payment> Payments => Set<Payment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(SchemaName);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(BookingDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
'@

# ===========================================================================
# Infrastructure DI update
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure DI update ==="

Write-File "$bi/DependencyInjection.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Integration.FlightCatalog;
using Bookings.Infrastructure.Integration.Payment;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.Persistence;
using Bookings.Infrastructure.Persistence.Repositories;
using Bookings.Infrastructure.Persistence.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace Bookings.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddBookingsInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Booking")
            ?? throw new InvalidOperationException("Connection string 'Booking' is not configured.");

        services.AddDbContext<BookingDbContext>(opts =>
            opts.UseNpgsql(connectionString, npgsql =>
                npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "booking")));

        services.AddSingleton<NpgsqlDataSource>(sp => NpgsqlDataSource.Create(connectionString));

        services.AddScoped<IBookingRepository, BookingRepository>();
        services.AddScoped<IBookingReadRepository, BookingReadRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        // Cross-module adapter (ADR-005, SPEC-003.2 AD-3).
        services.AddScoped<IFlightCatalogClient, FlightCatalogClient>();

        // Saga dependencies.
        services.Configure<PaymentOptions>(configuration.GetSection(PaymentOptions.SectionName));
        services.AddScoped<ISeatReservationService, SeatReservationService>();
        services.AddScoped<IPaymentGateway, FakePaymentGateway>();

        return services;
    }
}
'@

# ===========================================================================
# Infrastructure csproj (add Options.ConfigurationExtensions)
# ===========================================================================
Write-Host ""
Write-Host "=== Infrastructure csproj update ==="

Write-File "$bi/Bookings.Infrastructure.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>Bookings.Infrastructure</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Relational" Version="9.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="9.0.0">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="9.0.0" />
    <PackageReference Include="Dapper" Version="2.1.35" />
    <PackageReference Include="Npgsql" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.Options" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.Options.ConfigurationExtensions" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\Bookings.Application\Bookings.Application.csproj" />
    <ProjectReference Include="..\..\FlightCatalog\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

# ===========================================================================
# T-16: Endpoints update
# ===========================================================================
Write-Host ""
Write-Host "=== T-16. Endpoints update ==="

Write-File "$bp/Contracts/CancelBookingRequest.cs" @'
namespace Bookings.Api.Contracts;

public sealed record CancelBookingRequest(string Reason);
'@

Write-File "$bp/BookingsEndpoints.cs" @'
using Bookings.Api.Contracts;
using Bookings.Application.Commands.AddTicket;
using Bookings.Application.Commands.CancelBooking;
using Bookings.Application.Commands.ConfirmBooking;
using Bookings.Application.Commands.CreateBooking;
using Bookings.Application.Queries.GetBookingById;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace Bookings.Api;

public static class BookingsEndpoints
{
    public static IEndpointRouteBuilder MapBookingsEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/bookings").WithTags("Bookings");

        group.MapPost("/", async (
            CreateBookingRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new CreateBookingCommand(req.PassengerId, req.PassengerName, req.Currency);
            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/bookings/{result.Value}", new { id = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapGet("/{id:guid}", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetBookingByIdQuery(id), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapPost("/{id:guid}/tickets", async (
            Guid id,
            AddTicketRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new AddTicketCommand(
                id, req.FlightId, req.PassengerId, req.PassengerName, req.Amount);

            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/bookings/{id}/tickets/{result.Value}",
                    new { ticketId = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/confirm", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new ConfirmBookingCommand(id), ct);
            return result.IsSuccess
                ? Results.Ok(result.Value)
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/cancel", async (
            Guid id,
            CancelBookingRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new CancelBookingCommand(id, req.Reason), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        return app;
    }
}
'@

# ===========================================================================
# Host appsettings update (Payment section)
# ===========================================================================
Write-Host ""
Write-Host "=== Host appsettings ==="

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
    "MaxDelayMs": 500
  },
  "AllowedHosts": "*"
}
'@

# ===========================================================================
# Tests
# ===========================================================================
Write-Host ""
Write-Host "=== Tests ==="

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
}
'@

Write-File "$tests/Application/CancelBookingCommandHandlerTests.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.Commands.CancelBooking;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class CancelBookingCommandHandlerTests
{
    private static Booking MakeBooking()
        => Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static CancelBookingCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<ISeatReservationService> seats)
        => new(repo.Object, uow.Object, seats.Object,
               NullLogger<CancelBookingCommandHandler>.Instance);

    [Fact]
    public async Task Handle_PendingBooking_CancelsAndReleasesSeats()
    {
        var booking = MakeBooking();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReleaseAllForBookingAsync(booking.Id, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var handler = Build(repo, uow, seats);

        var result = await handler.Handle(
            new CancelBookingCommand(booking.Id, "changed plans"), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        booking.Status.Should().Be(BookingStatus.Cancelled);
        seats.Verify(s => s.ReleaseAllForBookingAsync(booking.Id, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_BookingNotFound_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Booking?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<ISeatReservationService>());

        var result = await handler.Handle(
            new CancelBookingCommand(Guid.NewGuid(), "test"), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_AlreadyCancelled_ReturnsDomainError()
    {
        var booking = MakeBooking();
        booking.Cancel("first");

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<ISeatReservationService>());

        var result = await handler.Handle(
            new CancelBookingCommand(booking.Id, "again"), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("domain_error");
    }
}
'@

# ===========================================================================
# T-18: ADR-006
# ===========================================================================
Write-Host ""
Write-Host "=== T-18. ADR-006 ==="

Write-File "docs/adr/ADR-006-saga-orchestration.md" @'
# ADR-006: Saga Orchestration for Booking Confirmation

## Status
Accepted

## Context
Confirming a booking spans three logical steps that touch different concerns:
1. Verifying each ticket's flight in FlightCatalog.
2. Reserving seats (in a future extraction: a separate inventory service).
3. Charging payment via an external gateway.

These steps cannot be wrapped in a single database transaction because:
- Payment gateway is an external system (no 2PC available).
- In the near future, FlightCatalog and Bookings will be separate services.

The platform must guarantee eventual consistency: either the booking is fully
confirmed, or no side effects remain.

## Decision
Use an **orchestration saga** implemented in `ConfirmBookingCommandHandler`.

Steps and compensations:

    Step 1: verify flights (read-only)           -> no compensation
    Step 2: reserve seats                        -> compensate: release seats
    Step 3: charge payment                       -> compensate: refund payment
    Step 4: mark booking Confirmed (local)       -> compensate: mark Expired

On any failure the handler runs compensations in reverse order, then marks the
booking as `Expired`. Compensations are idempotent - running them twice is safe.

Each step persists its result independently (separate `SaveChangesAsync`) so
that the compensation has something concrete to reverse and the audit trail
is complete.

The saga is currently **in-process** (MediatR). When the modules are extracted
into services, the same orchestration is expressed as a MassTransit state
machine with no changes to the domain.

## Consequences
Positive:
- No distributed transactions needed.
- Clear, debuggable, testable flow - all steps visible in one handler.
- Compensation logic is domain-adjacent and easy to unit test.
- Ports to MassTransit State Machine without domain changes.

Negative:
- Eventual consistency window: for a brief moment, seats may be reserved
  without a confirmed booking. Acceptable for our domain.
- Handler has more dependencies than a typical command handler.
- Compensations themselves can fail; we log and continue to avoid cascading.

## Alternatives considered
- **2PC (two-phase commit)** - rejected: payment gateway does not support it,
  and future services cannot participate.
- **Choreography (events between modules)** - rejected: the flow is linear and
  small; explicit orchestration is easier to reason about and test. When the
  flow grows or participants multiply, we may revisit.
- **Single local transaction with no compensations** - rejected: cannot span
  external systems.

## References
- SPEC-003.2 Section 7 (saga flow)
- ADR-005 (Bookings as a separate bounded context)
'@

# ===========================================================================
# Clean + build
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

# ===========================================================================
# T-11: Generate migration AddBookingSagaTables
# ===========================================================================
Write-Host ""
Write-Host "=== T-11. Generate migration AddBookingSagaTables ==="

$env:BOOKING_CONNECTION = "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"
$biCsproj = "$bi/Bookings.Infrastructure.csproj"

dotnet ef migrations add AddBookingSagaTables `
    --project $biCsproj `
    --startup-project $biCsproj `
    --context BookingDbContext `
    --output-dir "Persistence/Migrations"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "MIGRATION GENERATION FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + migration generated"

# ===========================================================================
# Apply migration
# ===========================================================================
Write-Host ""
Write-Host "=== Apply migration ==="

dotnet ef database update `
    --project $biCsproj `
    --startup-project $biCsproj `
    --context BookingDbContext

if ($LASTEXITCODE -ne 0) {
    Write-Host "MIGRATION APPLY FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + migration applied"

# ===========================================================================
# Tests
# ===========================================================================
Write-Host ""
Write-Host "=== dotnet test ==="
dotnet test --no-build --nologo

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "New tables in booking schema:" -ForegroundColor Yellow
Write-Host "  booking.seat_reservations"
Write-Host "  booking.payments"
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""
Write-Host "Scenario 1 - happy path:"
Write-Host "  1. POST /bookings { ... }"
Write-Host "  2. POST /bookings/{id}/tickets { flightId, ..., amount }"
Write-Host "  3. POST /bookings/{id}/confirm"
Write-Host "     -> expect: { bookingId, confirmed: true, failureReason: null }"
Write-Host ""
Write-Host "Scenario 2 - compensation:"
Write-Host "  1. Set Payment.FailureRatePercent=100 in appsettings, restart API"
Write-Host "  2. Repeat steps 1-3 above"
Write-Host "     -> expect: 400 saga_failed"
Write-Host "     -> booking status = Expired (2), seat_reservations status = Released (1)"
Write-Host "     -> logs show compensation steps"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(bookings): phase 3.2.2 - ConfirmBooking saga with compensations"'
Write-Host "  git push"
Write-Host ""
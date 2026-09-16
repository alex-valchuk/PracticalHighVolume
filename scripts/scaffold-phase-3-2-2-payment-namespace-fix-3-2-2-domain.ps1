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
Write-Host "=== Fix: rename namespace Payment -> Payments ==="
Write-Host ""

# 1. Remove old folder
$oldDir = "src/Modules/Bookings/Bookings.Infrastructure/Integration/Payment"
if (Test-Path -LiteralPath $oldDir) {
    Remove-Item -LiteralPath $oldDir -Recurse -Force
    Write-Host "  + deleted old folder Integration/Payment"
}

# 2. Write file in new location
$newPath = "src/Modules/Bookings/Bookings.Infrastructure/Integration/Payments/FakePaymentGateway.cs"

Write-File $newPath @'
using Bookings.Application.Abstractions;
using Bookings.Domain.Aggregates;
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

# 3. Update DependencyInjection.cs
Write-File "src/Modules/Bookings/Bookings.Infrastructure/DependencyInjection.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Integration.FlightCatalog;
using Bookings.Infrastructure.Integration.Payments;
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

        services.AddScoped<IFlightCatalogClient, FlightCatalogClient>();

        services.Configure<PaymentOptions>(configuration.GetSection(PaymentOptions.SectionName));
        services.AddScoped<ISeatReservationService, SeatReservationService>();
        services.AddScoped<IPaymentGateway, FakePaymentGateway>();

        return services;
    }
}
'@

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
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Next step - migration (from 3.2.2):" -ForegroundColor Yellow
Write-Host '  $env:BOOKING_CONNECTION = "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"'
Write-Host "  dotnet ef migrations add AddBookingSagaTables --project src/Modules/Bookings/Bookings.Infrastructure/Bookings.Infrastructure.csproj --startup-project src/Modules/Bookings/Bookings.Infrastructure/Bookings.Infrastructure.csproj --context BookingDbContext --output-dir Persistence/Migrations"
Write-Host "  dotnet ef database update --project src/Modules/Bookings/Bookings.Infrastructure/Bookings.Infrastructure.csproj --startup-project src/Modules/Bookings/Bookings.Infrastructure/Bookings.Infrastructure.csproj --context BookingDbContext"
Write-Host ""
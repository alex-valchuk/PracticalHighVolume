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
Write-Host "=== Fix: ensure all 3.2.2 domain files exist ==="
Write-Host ""

$bd = "src/Modules/Bookings/Bookings.Domain"

# --- Check what exists ---
$needed = @(
    "SeatReservationStatus.cs",
    "PaymentStatus.cs",
    "Aggregates/SeatReservation.cs",
    "Aggregates/Payment.cs"
)

Write-Host "Checking existing files:"
foreach ($f in $needed) {
    $path = Join-Path (Get-Location).Path "$bd/$f"
    if (Test-Path -LiteralPath $path) {
        Write-Host ("  OK   " + $f) -ForegroundColor Green
    } else {
        Write-Host ("  MISS " + $f) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== (Re)writing all domain files for 3.2.2 ==="
Write-Host ""

Write-File "$bd/SeatReservationStatus.cs" @'
namespace Bookings.Domain;

public enum SeatReservationStatus
{
    Active = 0,
    Released = 1
}
'@

Write-File "$bd/PaymentStatus.cs" @'
namespace Bookings.Domain;

public enum PaymentStatus
{
    Charged = 0,
    Refunded = 1,
    Failed = 2
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
Write-Host "If build/tests are green - continue with the migration step from 3.2.2:" -ForegroundColor Yellow
Write-Host "  dotnet ef migrations add AddBookingSagaTables ..."
Write-Host ""
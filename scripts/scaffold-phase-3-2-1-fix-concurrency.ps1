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
Write-Host "=== Fix: DbUpdateConcurrencyException on owned Ticket ==="
Write-Host ""

# 1. Patch BookingConfiguration: ValueGeneratedNever for Ticket.Id
Write-File "src/Modules/Bookings/Bookings.Infrastructure/Persistence/Configurations/BookingConfiguration.cs" @'
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Bookings.Infrastructure.Persistence.Configurations;

public sealed class BookingConfiguration : IEntityTypeConfiguration<Booking>
{
    public void Configure(EntityTypeBuilder<Booking> builder)
    {
        builder.ToTable("bookings");
        builder.HasKey(b => b.Id);
        builder.Property(b => b.Id).HasColumnName("id");

        builder.Property(b => b.BookDate).HasColumnName("book_date").IsRequired();

        builder.Property(b => b.Status)
            .HasColumnName("status")
            .HasConversion<int>()
            .IsRequired();

        builder.Property(b => b.BookRef)
            .HasConversion(br => br.Value, v => BookingReference.Create(v))
            .HasColumnName("book_ref")
            .HasMaxLength(6)
            .IsRequired();

        builder.Property(b => b.PassengerId)
            .HasConversion(pid => pid.Value, v => PassengerId.Create(v))
            .HasColumnName("passenger_id")
            .HasMaxLength(20)
            .IsRequired();

        builder.Property(b => b.PassengerName)
            .HasConversion(pn => pn.Value, v => PassengerName.Create(v))
            .HasColumnName("passenger_name")
            .HasMaxLength(200)
            .IsRequired();

        builder.OwnsOne(b => b.TotalAmount, m =>
        {
            m.Property(x => x.Amount).HasColumnName("total_amount").HasPrecision(18, 2).IsRequired();
            m.Property(x => x.Currency).HasColumnName("currency").HasMaxLength(3).IsRequired();
        });

        builder.OwnsMany(b => b.Tickets, t =>
        {
            t.ToTable("tickets");
            t.WithOwner().HasForeignKey("booking_id");
            t.HasKey(x => x.Id);

            // KEY FIX: the Id is generated in code, not by the database.
            // Without ValueGeneratedNever, EF Core treats the new entity as
            // "modified" and issues UPDATE instead of INSERT.
            t.Property(x => x.Id)
                .HasColumnName("id")
                .ValueGeneratedNever();

            t.Property(x => x.TicketNo).HasColumnName("ticket_no").HasMaxLength(20).IsRequired();
            t.Property(x => x.FlightId).HasColumnName("flight_id").IsRequired();
            t.Property(x => x.Amount).HasColumnName("amount").HasPrecision(18, 2).IsRequired();

            t.Property(x => x.PassengerId)
                .HasConversion(pid => pid.Value, v => PassengerId.Create(v))
                .HasColumnName("passenger_id")
                .HasMaxLength(20)
                .IsRequired();

            t.Property(x => x.PassengerName)
                .HasConversion(pn => pn.Value, v => PassengerName.Create(v))
                .HasColumnName("passenger_name")
                .HasMaxLength(200)
                .IsRequired();

            t.HasIndex("booking_id");
        });

        builder.HasIndex(b => b.BookRef).IsUnique();
    }
}
'@

# 2. Patch AddTicketCommandHandler: remove Update() call
Write-File "src/Modules/Bookings/Bookings.Application/Commands/AddTicket/AddTicketCommandHandler.cs" @'
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
'@

# 3. Ensure repository has Update() (used elsewhere) but doesn't break tracking
Write-File "src/Modules/Bookings/Bookings.Infrastructure/Persistence/Repositories/BookingRepository.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Domain.Aggregates;
using Microsoft.EntityFrameworkCore;

namespace Bookings.Infrastructure.Persistence.Repositories;

public sealed class BookingRepository : IBookingRepository
{
    private readonly BookingDbContext _db;

    public BookingRepository(BookingDbContext db) => _db = db;

    public Task<Booking?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => _db.Bookings.FirstOrDefaultAsync(b => b.Id == id, ct);

    public async Task AddAsync(Booking booking, CancellationToken ct = default)
        => await _db.Bookings.AddAsync(booking, ct);

    // Keep Update() for command handlers that load a detached aggregate.
    // For tracked aggregates (like AddTicket), callers should NOT call Update().
    public void Update(Booking booking) => _db.Bookings.Update(booking);
}
'@

Write-Host ""
Write-Host "=== Clean + build ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

Write-Host ""
Write-Host "=== dotnet test ==="
dotnet test --no-build --nologo

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Restart the API and try AddTicket again." -ForegroundColor Yellow
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(bookings): ValueGeneratedNever for Ticket.Id + remove Update() on tracked aggregate"'
Write-Host "  git push"
Write-Host ""
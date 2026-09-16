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
Write-Host "=== PHASE 3.1 - Bookings module (single script, no manual steps) ==="
Write-Host ("Working dir: " + (Get-Location).Path)
Write-Host ""

$sln = Get-ChildItem -Filter "*.slnx" -File | Select-Object -First 1
if (-not $sln) { $sln = Get-ChildItem -Filter "*.sln" -File | Select-Object -First 1 }
if (-not $sln) { Write-Host "Solution not found" -ForegroundColor Red; exit 1 }
Write-Host ("Solution: " + $sln.Name)
Write-Host ""

$bd = "src/Modules/Bookings/Bookings.Domain"
$ba = "src/Modules/Bookings/Bookings.Application"
$bi = "src/Modules/Bookings/Bookings.Infrastructure"
$bp = "src/Modules/Bookings/Bookings.Api"
$hostDir = "src/Hosts/FlightsPlatform.Api"
$tests = "tests/Bookings.UnitTests"

# ===========================================================================
# 1. HOST CSPROJ - full overwrite, no regex
# ===========================================================================
Write-Host "=== 1. Host csproj (full overwrite) ==="

Write-File "$hostDir/FlightsPlatform.Api.csproj" @'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <RootNamespace>FlightsPlatform.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="10.0.0" />
    <PackageReference Include="Scalar.AspNetCore" Version="2.0.0" />
    <PackageReference Include="Serilog.AspNetCore" Version="8.0.3" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Api\FlightCatalog.Api.csproj" />
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Infrastructure\FlightCatalog.Infrastructure.csproj" />
    <ProjectReference Include="..\..\Modules\FlightCatalog\FlightCatalog.Application\FlightCatalog.Application.csproj" />
    <ProjectReference Include="..\..\Modules\Bookings\Bookings.Api\Bookings.Api.csproj" />
    <ProjectReference Include="..\..\Modules\Bookings\Bookings.Infrastructure\Bookings.Infrastructure.csproj" />
    <ProjectReference Include="..\..\Modules\Bookings\Bookings.Application\Bookings.Application.csproj" />
  </ItemGroup>
</Project>
'@

# ===========================================================================
# 2. BOOKINGS DOMAIN
# ===========================================================================
Write-Host ""
Write-Host "=== 2. Bookings.Domain ==="

Write-File "$bd/Bookings.Domain.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>Bookings.Domain</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\..\BuildingBlocks\FlightsPlatform.SharedKernel\FlightsPlatform.SharedKernel.csproj" />
  </ItemGroup>
</Project>
'@

Write-File "$bd/BookingStatus.cs" @'
namespace Bookings.Domain;

public enum BookingStatus
{
    Pending = 0,
    Confirmed = 1,
    Cancelled = 2,
    Expired = 3
}
'@

Write-File "$bd/ValueObjects/BookingReference.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class BookingReference : ValueObject
{
    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    private static readonly Random Rng = new();

    public string Value { get; private set; } = default!;

    private BookingReference() { }
    private BookingReference(string value) => Value = value;

    public static BookingReference Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Booking reference cannot be empty.");

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length != 6 || !normalized.All(char.IsLetterOrDigit))
            throw new DomainException("Booking reference must be exactly 6 alphanumeric characters.");

        return new BookingReference(normalized);
    }

    public static BookingReference Generate()
    {
        Span<char> buffer = stackalloc char[6];
        for (int i = 0; i < 6; i++)
            buffer[i] = Alphabet[Rng.Next(Alphabet.Length)];
        return new BookingReference(new string(buffer));
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
'@

Write-File "$bd/ValueObjects/Money.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class Money : ValueObject
{
    public decimal Amount { get; private set; }
    public string Currency { get; private set; } = default!;

    private Money() { }

    private Money(decimal amount, string currency)
    {
        Amount = amount;
        Currency = currency;
    }

    public static Money Create(decimal amount, string currency)
    {
        if (amount < 0)
            throw new DomainException("Amount cannot be negative.");
        if (string.IsNullOrWhiteSpace(currency) || currency.Length != 3)
            throw new DomainException("Currency must be a 3-letter ISO code.");

        return new Money(decimal.Round(amount, 2), currency.ToUpperInvariant());
    }

    public static Money Zero(string currency) => Create(0m, currency);

    public Money Add(Money other)
    {
        if (Currency != other.Currency)
            throw new DomainException("Cannot add Money with different currencies.");
        return new Money(Amount + other.Amount, Currency);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Amount;
        yield return Currency;
    }

    public override string ToString() => Amount.ToString("0.00") + " " + Currency;
}
'@

Write-File "$bd/ValueObjects/PassengerId.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class PassengerId : ValueObject
{
    public string Value { get; private set; } = default!;

    private PassengerId() { }
    private PassengerId(string value) => Value = value;

    public static PassengerId Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Passenger id cannot be empty.");

        var normalized = value.Trim();
        if (normalized.Length < 5 || normalized.Length > 20)
            throw new DomainException("Passenger id must be 5-20 characters.");

        return new PassengerId(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
'@

Write-File "$bd/ValueObjects/PassengerName.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.ValueObjects;

public sealed class PassengerName : ValueObject
{
    public string Value { get; private set; } = default!;

    private PassengerName() { }
    private PassengerName(string value) => Value = value;

    public static PassengerName Create(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Passenger name cannot be empty.");

        var normalized = value.Trim();
        if (normalized.Length > 200)
            throw new DomainException("Passenger name is too long.");

        return new PassengerName(normalized);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;
}
'@

Write-File "$bd/Events/BookingCreated.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingCreated(
    Guid BookingId,
    string BookingReference,
    string PassengerId,
    string Currency) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-File "$bd/Events/BookingCancelled.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingCancelled(
    Guid BookingId,
    string BookingReference,
    string Reason) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-File "$bd/Aggregates/Ticket.cs" @'
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Aggregates;

public sealed class Ticket : Entity<Guid>
{
    public string TicketNo { get; private set; } = default!;
    public PassengerId PassengerId { get; private set; } = default!;
    public PassengerName PassengerName { get; private set; } = default!;
    public Guid FlightId { get; private set; }
    public decimal Amount { get; private set; }

    private Ticket() { }

    internal Ticket(
        Guid id,
        string ticketNo,
        PassengerId passengerId,
        PassengerName passengerName,
        Guid flightId,
        decimal amount) : base(id)
    {
        TicketNo = ticketNo;
        PassengerId = passengerId;
        PassengerName = passengerName;
        FlightId = flightId;
        Amount = amount;
    }
}
'@

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
# 3. BOOKINGS APPLICATION
# ===========================================================================
Write-Host ""
Write-Host "=== 3. Bookings.Application ==="

Write-File "$ba/Bookings.Application.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>Bookings.Application</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="FluentValidation" Version="11.10.0" />
    <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.10.0" />
    <PackageReference Include="Dapper" Version="2.1.35" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="9.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\Bookings.Domain\Bookings.Domain.csproj" />
    <ProjectReference Include="..\..\..\BuildingBlocks\FlightsPlatform.Application.Abstractions\FlightsPlatform.Application.Abstractions.csproj" />
  </ItemGroup>
</Project>
'@

Write-File "$ba/Abstractions/IBookingRepository.cs" @'
using Bookings.Domain.Aggregates;

namespace Bookings.Application.Abstractions;

public interface IBookingRepository
{
    Task<Booking?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task AddAsync(Booking booking, CancellationToken ct = default);
    void Update(Booking booking);
}
'@

Write-File "$ba/Abstractions/IBookingReadRepository.cs" @'
using Bookings.Application.DTOs;

namespace Bookings.Application.Abstractions;

public interface IBookingReadRepository
{
    Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default);
}
'@

Write-File "$ba/Abstractions/IUnitOfWork.cs" @'
namespace Bookings.Application.Abstractions;

public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
'@

Write-File "$ba/DTOs/BookingDto.cs" @'
namespace Bookings.Application.DTOs;

public sealed class BookingDto
{
    public Guid Id { get; init; }
    public string BookRef { get; init; } = default!;
    public DateTimeOffset BookDate { get; init; }
    public decimal TotalAmount { get; init; }
    public string Currency { get; init; } = default!;
    public int Status { get; init; }
    public string PassengerId { get; init; } = default!;
    public string PassengerName { get; init; } = default!;
    public List<TicketDto> Tickets { get; init; } = new();
}

public sealed class TicketDto
{
    public Guid Id { get; init; }
    public string TicketNo { get; init; } = default!;
    public Guid FlightId { get; init; }
    public decimal Amount { get; init; }
}
'@

Write-File "$ba/Commands/CreateBooking/CreateBookingCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.CreateBooking;

public sealed record CreateBookingCommand(
    string PassengerId,
    string PassengerName,
    string Currency) : IRequest<Result<Guid>>;
'@

Write-File "$ba/Commands/CreateBooking/CreateBookingCommandValidator.cs" @'
using FluentValidation;

namespace Bookings.Application.Commands.CreateBooking;

public sealed class CreateBookingCommandValidator : AbstractValidator<CreateBookingCommand>
{
    public CreateBookingCommandValidator()
    {
        RuleFor(x => x.PassengerId).NotEmpty().Length(5, 20);
        RuleFor(x => x.PassengerName).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Currency).NotEmpty().Length(3);
    }
}
'@

Write-File "$ba/Commands/CreateBooking/CreateBookingCommandHandler.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.CreateBooking;

public sealed class CreateBookingCommandHandler : IRequestHandler<CreateBookingCommand, Result<Guid>>
{
    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<CreateBookingCommandHandler> _logger;

    public CreateBookingCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        ILogger<CreateBookingCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    public async Task<Result<Guid>> Handle(CreateBookingCommand request, CancellationToken ct)
    {
        try
        {
            var booking = Booking.CreateDraft(
                PassengerId.Create(request.PassengerId),
                PassengerName.Create(request.PassengerName),
                request.Currency);

            await _repository.AddAsync(booking, ct);
            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation("Created booking {BookingId} ({BookRef})",
                booking.Id, booking.BookRef.Value);

            return Result<Guid>.Success(booking.Id);
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "Domain rule violated while creating booking");
            return Result<Guid>.Failure(ex.Message, "domain_error");
        }
    }
}
'@

Write-File "$ba/Queries/GetBookingById/GetBookingByIdQuery.cs" @'
using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingById;

public sealed record GetBookingByIdQuery(Guid BookingId) : IRequest<BookingDto?>;
'@

Write-File "$ba/Queries/GetBookingById/GetBookingByIdQueryHandler.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingById;

public sealed class GetBookingByIdQueryHandler : IRequestHandler<GetBookingByIdQuery, BookingDto?>
{
    private readonly IBookingReadRepository _readRepository;

    public GetBookingByIdQueryHandler(IBookingReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<BookingDto?> Handle(GetBookingByIdQuery request, CancellationToken ct)
        => _readRepository.GetByIdAsync(request.BookingId, ct);
}
'@

Write-File "$ba/Behaviors/LoggingBehavior.cs" @'
using System.Diagnostics;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Behaviors;

public sealed class LoggingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<LoggingBehavior<TRequest, TResponse>> _logger;

    public LoggingBehavior(ILogger<LoggingBehavior<TRequest, TResponse>> logger)
        => _logger = logger;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var name = typeof(TRequest).Name;
        _logger.LogInformation("[Bookings] Handling {RequestName}", name);

        var sw = Stopwatch.StartNew();
        try
        {
            var response = await next();
            sw.Stop();
            _logger.LogInformation("[Bookings] Handled {RequestName} in {Elapsed} ms",
                name, sw.ElapsedMilliseconds);
            return response;
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex, "[Bookings] Error handling {RequestName} after {Elapsed} ms",
                name, sw.ElapsedMilliseconds);
            throw;
        }
    }
}
'@

Write-File "$ba/Behaviors/ValidationBehavior.cs" @'
using FluentValidation;
using MediatR;

namespace Bookings.Application.Behaviors;

public sealed class ValidationBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehavior(IEnumerable<IValidator<TRequest>> validators)
        => _validators = validators;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (!_validators.Any())
            return await next();

        var context = new ValidationContext<TRequest>(request);
        var results = await Task.WhenAll(_validators.Select(v => v.ValidateAsync(context, ct)));
        var failures = results.SelectMany(r => r.Errors).Where(f => f is not null).ToList();

        if (failures.Count != 0)
            throw new ValidationException(failures);

        return await next();
    }
}
'@

Write-File "$ba/DependencyInjection.cs" @'
using System.Reflection;
using Bookings.Application.Behaviors;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace Bookings.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddBookingsApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();

        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(assembly);
            cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        });

        services.AddValidatorsFromAssembly(assembly, includeInternalTypes: true);

        return services;
    }
}
'@

# ===========================================================================
# 4. BOOKINGS INFRASTRUCTURE
# ===========================================================================
Write-Host ""
Write-Host "=== 4. Bookings.Infrastructure ==="

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
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\Bookings.Application\Bookings.Application.csproj" />
  </ItemGroup>
</Project>
'@

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

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(SchemaName);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(BookingDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
'@

Write-File "$bi/Persistence/Configurations/BookingConfiguration.cs" @'
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

            t.Property(x => x.Id).HasColumnName("id");
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

Write-File "$bi/Persistence/Repositories/BookingRepository.cs" @'
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

    public void Update(Booking booking) => _db.Bookings.Update(booking);
}
'@

Write-File "$bi/Persistence/Repositories/BookingReadRepository.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using Dapper;
using Npgsql;

namespace Bookings.Infrastructure.Persistence.Repositories;

public sealed class BookingReadRepository : IBookingReadRepository
{
    private readonly NpgsqlDataSource _dataSource;

    public BookingReadRepository(NpgsqlDataSource dataSource) => _dataSource = dataSource;

    public async Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        const string sqlBooking = @"
            SELECT id             AS Id,
                   book_ref       AS BookRef,
                   book_date      AS BookDate,
                   total_amount   AS TotalAmount,
                   currency       AS Currency,
                   status         AS Status,
                   passenger_id   AS PassengerId,
                   passenger_name AS PassengerName
            FROM booking.bookings
            WHERE id = @Id";

        const string sqlTickets = @"
            SELECT id        AS Id,
                   ticket_no AS TicketNo,
                   flight_id AS FlightId,
                   amount    AS Amount
            FROM booking.tickets
            WHERE booking_id = @Id
            ORDER BY ticket_no";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);

        var booking = await conn.QueryFirstOrDefaultAsync<BookingDto>(
            new CommandDefinition(sqlBooking, new { Id = id }, cancellationToken: ct));

        if (booking is null) return null;

        var tickets = await conn.QueryAsync<TicketDto>(
            new CommandDefinition(sqlTickets, new { Id = id }, cancellationToken: ct));

        booking.Tickets.AddRange(tickets);
        return booking;
    }
}
'@

Write-File "$bi/Persistence/UnitOfWork.cs" @'
using Bookings.Application.Abstractions;

namespace Bookings.Infrastructure.Persistence;

public sealed class UnitOfWork : IUnitOfWork
{
    private readonly BookingDbContext _db;

    public UnitOfWork(BookingDbContext db) => _db = db;

    public Task<int> SaveChangesAsync(CancellationToken ct = default) => _db.SaveChangesAsync(ct);
}
'@

Write-File "$bi/Persistence/DesignTimeDbContextFactory.cs" @'
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Bookings.Infrastructure.Persistence;

internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<BookingDbContext>
{
    public BookingDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("BOOKING_CONNECTION")
            ?? "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password";

        var optionsBuilder = new DbContextOptionsBuilder<BookingDbContext>();
        optionsBuilder.UseNpgsql(connectionString, npgsql =>
            npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "booking"));

        return new BookingDbContext(optionsBuilder.Options);
    }
}
'@

Write-File "$bi/DependencyInjection.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Persistence;
using Bookings.Infrastructure.Persistence.Repositories;
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

        return services;
    }
}
'@

# ===========================================================================
# 5. BOOKINGS API
# ===========================================================================
Write-Host ""
Write-Host "=== 5. Bookings.Api ==="

Write-File "$bp/Bookings.Api.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>Bookings.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\Bookings.Application\Bookings.Application.csproj" />
  </ItemGroup>
</Project>
'@

Write-File "$bp/Contracts/CreateBookingRequest.cs" @'
namespace Bookings.Api.Contracts;

public sealed record CreateBookingRequest(
    string PassengerId,
    string PassengerName,
    string Currency);
'@

Write-File "$bp/BookingsEndpoints.cs" @'
using Bookings.Api.Contracts;
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

        return app;
    }
}
'@

# ===========================================================================
# 6. TESTS
# ===========================================================================
Write-Host ""
Write-Host "=== 6. Bookings.UnitTests ==="

Write-File "$tests/Bookings.UnitTests.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <RootNamespace>Bookings.UnitTests</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
    <PackageReference Include="FluentAssertions" Version="6.12.1" />
    <PackageReference Include="Moq" Version="4.20.72" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Modules\Bookings\Bookings.Application\Bookings.Application.csproj" />
  </ItemGroup>
</Project>
'@

Write-File "$tests/Domain/BookingReferenceTests.cs" @'
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingReferenceTests
{
    [Theory]
    [InlineData("ABC123")]
    [InlineData("abc123")]
    [InlineData(" ABC123 ")]
    public void Create_Valid_Normalizes(string input)
    {
        var r = BookingReference.Create(input);
        r.Value.Should().Be("ABC123");
    }

    [Theory]
    [InlineData("")]
    [InlineData("ABC12")]
    [InlineData("ABC1234")]
    [InlineData("ABC-12")]
    public void Create_Invalid_Throws(string input)
    {
        var act = () => BookingReference.Create(input);
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void Generate_ProducesValid()
    {
        var r = BookingReference.Generate();
        r.Value.Should().HaveLength(6);
        r.Value.Should().MatchRegex("^[A-Z0-9]{6}$");
    }
}
'@

Write-File "$tests/Domain/BookingTests.cs" @'
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingTests
{
    private static Booking Make() =>
        Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    [Fact]
    public void CreateDraft_RaisesEvent()
    {
        var b = Make();
        b.DomainEvents.Should().ContainSingle(e => e is BookingCreated);
        b.Status.Should().Be(BookingStatus.Pending);
        b.TotalAmount.Amount.Should().Be(0);
        b.TotalAmount.Currency.Should().Be("RUB");
    }

    [Fact]
    public void Cancel_OnPending_Succeeds()
    {
        var b = Make();
        b.ClearDomainEvents();

        b.Cancel("changed plans");

        b.Status.Should().Be(BookingStatus.Cancelled);
        b.DomainEvents.Should().ContainSingle(e => e is BookingCancelled);
    }

    [Fact]
    public void Cancel_OnCancelled_Throws()
    {
        var b = Make();
        b.Cancel("first");

        var act = () => b.Cancel("second");
        act.Should().Throw<DomainException>();
    }
}
'@

Write-File "$tests/Application/CreateBookingCommandHandlerTests.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.Commands.CreateBooking;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class CreateBookingCommandHandlerTests
{
    [Fact]
    public async Task Handle_WithValidRequest_ReturnsSuccess()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.AddAsync(It.IsAny<Bookings.Domain.Aggregates.Booking>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new CreateBookingCommandHandler(
            repo.Object, uow.Object, NullLogger<CreateBookingCommandHandler>.Instance);

        var result = await handler.Handle(
            new CreateBookingCommand("1234567890", "IVANOV IVAN", "RUB"),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();
        repo.Verify(r => r.AddAsync(It.IsAny<Bookings.Domain.Aggregates.Booking>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_WithInvalidPassengerId_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        var uow = new Mock<IUnitOfWork>();
        var handler = new CreateBookingCommandHandler(
            repo.Object, uow.Object, NullLogger<CreateBookingCommandHandler>.Instance);

        var result = await handler.Handle(
            new CreateBookingCommand("bad", "IVANOV IVAN", "RUB"),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
    }
}
'@

# ===========================================================================
# 7. PROGRAM.CS
# ===========================================================================
Write-Host ""
Write-Host "=== 7. Program.cs ==="

Write-File "$hostDir/Program.cs" @'
using Bookings.Api;
using Bookings.Application;
using Bookings.Infrastructure;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;
using FlightsPlatform.SharedKernel;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

builder.Services.AddFlightCatalogApplication();
builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

builder.Services.AddBookingsApplication();
builder.Services.AddBookingsInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseExceptionHandler(errApp => errApp.Run(async ctx =>
{
    var feature = ctx.Features.Get<IExceptionHandlerFeature>();
    var ex = feature?.Error;

    var (status, payload) = ex switch
    {
        ValidationException ve => (StatusCodes.Status400BadRequest,
            (object)new
            {
                error = "validation_failed",
                details = ve.Errors.Select(e => e.ErrorMessage)
            }),
        DomainException de => (StatusCodes.Status400BadRequest,
            new { error = "domain_error", message = de.Message }),
        _ => (StatusCodes.Status500InternalServerError,
            new { error = "internal_error" })
    };

    ctx.Response.StatusCode = status;
    await ctx.Response.WriteAsJsonAsync(payload);
}));

app.UseHttpsRedirection();
app.MapControllers();
app.MapFlightCatalogEndpoints();
app.MapAirportEndpoints();
app.MapBookingsEndpoints();

using (var scope = app.Services.CreateScope())
{
    var fcDb = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await fcDb.Database.MigrateAsync();

    var bkDb = scope.ServiceProvider.GetRequiredService<BookingDbContext>();
    await bkDb.Database.MigrateAsync();
}

app.Run();
'@

# ===========================================================================
# 8. APPSETTINGS
# ===========================================================================
Write-Host ""
Write-Host "=== 8. appsettings.json ==="

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
  "AllowedHosts": "*"
}
'@

# ===========================================================================
# 9. SOLUTION
# ===========================================================================
Write-Host ""
Write-Host "=== 9. Solution ==="

$toAdd = @(
    "$bd/Bookings.Domain.csproj",
    "$ba/Bookings.Application.csproj",
    "$bi/Bookings.Infrastructure.csproj",
    "$bp/Bookings.Api.csproj",
    "$tests/Bookings.UnitTests.csproj"
)
foreach ($p in $toAdd) {
    dotnet sln $sln.FullName add $p 2>$null | Out-Null
    Write-Host ("  + " + $p)
}

# ===========================================================================
# 10. CLEAN + BUILD
# ===========================================================================
Write-Host ""
Write-Host "=== 10. Clean + build ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED. Migration generation is skipped." -ForegroundColor Red
    Write-Host "Fix the errors above, then re-run this script." -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

# ===========================================================================
# 11. CLEAN STATE FOR BOOKINGS MIGRATION
# ===========================================================================
Write-Host ""
Write-Host "=== 11. Prepare clean state for Bookings migration ==="

$bookingsMigrations = "$bi/Persistence/Migrations"
if (Test-Path -LiteralPath $bookingsMigrations) {
    Remove-Item -LiteralPath $bookingsMigrations -Recurse -Force
    Write-Host "  + deleted old Bookings Migrations folder"
}

$container = "flights-postgres"
$running = docker ps --filter "name=$container" --format "{{.Names}}"
if ($running -eq $container) {
    docker exec $container psql -U flights -d flights_demo -c "DROP SCHEMA IF EXISTS booking CASCADE;" | Out-Null
    Write-Host "  + dropped schema booking"
} else {
    Write-Host "  ! container '$container' not running - cannot drop schema" -ForegroundColor Yellow
    Write-Host "  ! start it and re-run the script" -ForegroundColor Yellow
    exit 1
}

# ===========================================================================
# 12. GENERATE MIGRATION
# ===========================================================================
Write-Host ""
Write-Host "=== 12. Generate Bookings migration ==="

$env:BOOKING_CONNECTION = "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"

dotnet ef migrations add InitialCreate `
    --project "$bi/Bookings.Infrastructure.csproj" `
    --startup-project "$bi/Bookings.Infrastructure.csproj" `
    --context BookingDbContext `
    --output-dir "Persistence/Migrations"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "MIGRATION GENERATION FAILED" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $bookingsMigrations)) {
    Write-Host ""
    Write-Host "Migrations folder was not created - something is wrong." -ForegroundColor Red
    exit 1
}

Write-Host "  + migration files generated:"
Get-ChildItem $bookingsMigrations | ForEach-Object { Write-Host ("      " + $_.Name) }

# ===========================================================================
# 13. APPLY MIGRATION
# ===========================================================================
Write-Host ""
Write-Host "=== 13. Apply Bookings migration ==="

dotnet ef database update `
    --project "$bi/Bookings.Infrastructure.csproj" `
    --startup-project "$bi/Bookings.Infrastructure.csproj" `
    --context BookingDbContext

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "MIGRATION APPLY FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + migration applied to flights_demo"

# ===========================================================================
# 14. TESTS
# ===========================================================================
Write-Host ""
Write-Host "=== 14. dotnet test ==="
dotnet test --no-build --nologo

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""
Write-Host "  Scalar: https://localhost:50943/scalar/v1"
Write-Host "  POST /bookings with:"
Write-Host '    { "passengerId": "1234567890", "passengerName": "IVANOV IVAN", "currency": "RUB" }'
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(bookings): phase 3.1 - module skeleton"'
Write-Host "  git push"
Write-Host ""
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
Write-Host "=== SPEC-003.2 - Script 3.2.1 ==="
Write-Host "Add ticket to booking + IFlightCatalogClient + tests"
Write-Host ""

$bd = "src/Modules/Bookings/Bookings.Domain"
$ba = "src/Modules/Bookings/Bookings.Application"
$bi = "src/Modules/Bookings/Bookings.Infrastructure"
$bp = "src/Modules/Bookings/Bookings.Api"
$tests = "tests/Bookings.UnitTests"

# ===========================================================================
# T-02: Domain events
# ===========================================================================
Write-Host "=== T-02. Domain events ==="

Write-File "$bd/Events/TicketAdded.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record TicketAdded(
    Guid BookingId,
    Guid TicketId,
    Guid FlightId,
    decimal Amount,
    string Currency) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-File "$bd/Events/BookingConfirmed.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingConfirmed(
    Guid BookingId,
    string BookingReference,
    decimal TotalAmount,
    string Currency) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

Write-File "$bd/Events/BookingExpired.cs" @'
using FlightsPlatform.SharedKernel;

namespace Bookings.Domain.Events;

public sealed record BookingExpired(
    Guid BookingId,
    string BookingReference,
    string Reason) : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}
'@

# ===========================================================================
# T-01: Extend Booking aggregate
# ===========================================================================
Write-Host ""
Write-Host "=== T-01. Booking aggregate extended ==="

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
# T-03, T-04: IFlightCatalogClient implementation + project reference
# ===========================================================================
Write-Host ""
Write-Host "=== T-03, T-04. FlightCatalogClient + project ref ==="

Write-File "$bi/Integration/FlightCatalog/FlightCatalogClient.cs" @'
using Bookings.Application.Abstractions;
using FlightCatalog.Application.Queries.GetFlightById;
using MediatR;

namespace Bookings.Infrastructure.Integration.FlightCatalog;

/// <summary>
/// Adapter that calls the FlightCatalog module via MediatR.
/// This is the only place in Bookings.Infrastructure that knows
/// about FlightCatalog.Application contracts.
/// </summary>
internal sealed class FlightCatalogClient : IFlightCatalogClient
{
    private readonly IMediator _mediator;

    public FlightCatalogClient(IMediator mediator) => _mediator = mediator;

    public async Task<FlightSummary?> GetFlightAsync(Guid flightId, CancellationToken ct = default)
    {
        var dto = await _mediator.Send(new GetFlightByIdQuery(flightId), ct);
        if (dto is null) return null;

        return new FlightSummary(
            dto.Id,
            dto.FlightNumber,
            dto.DepartureAirport,
            dto.ArrivalAirport,
            dto.ScheduledDeparture,
            dto.ScheduledArrival,
            dto.Status);
    }
}
'@

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
    <ProjectReference Include="..\..\FlightCatalog\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@

Write-File "$bi/DependencyInjection.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Integration.FlightCatalog;
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

        // Cross-module adapter (see ADR-005 and SPEC-003.2 AD-3).
        services.AddScoped<IFlightCatalogClient, FlightCatalogClient>();

        return services;
    }
}
'@

# ===========================================================================
# T-05: AddTicketCommand + handler + validator
# ===========================================================================
Write-Host ""
Write-Host "=== T-05. AddTicketCommand ==="

Write-File "$ba/Commands/AddTicket/AddTicketCommand.cs" @'
using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace Bookings.Application.Commands.AddTicket;

public sealed record AddTicketCommand(
    Guid BookingId,
    Guid FlightId,
    string PassengerId,
    string PassengerName,
    decimal Amount) : IRequest<Result<Guid>>;
'@

Write-File "$ba/Commands/AddTicket/AddTicketCommandValidator.cs" @'
using FluentValidation;

namespace Bookings.Application.Commands.AddTicket;

public sealed class AddTicketCommandValidator : AbstractValidator<AddTicketCommand>
{
    public AddTicketCommandValidator()
    {
        RuleFor(x => x.BookingId).NotEmpty();
        RuleFor(x => x.FlightId).NotEmpty();
        RuleFor(x => x.PassengerId).NotEmpty().Length(5, 20);
        RuleFor(x => x.PassengerName).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Amount).GreaterThan(0);
    }
}
'@

Write-File "$ba/Commands/AddTicket/AddTicketCommandHandler.cs" @'
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

            _repository.Update(booking);
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

# ===========================================================================
# T-06: Endpoint POST /bookings/{id}/tickets
# ===========================================================================
Write-Host ""
Write-Host "=== T-06. Endpoint POST /bookings/{id}/tickets ==="

Write-File "$bp/Contracts/AddTicketRequest.cs" @'
namespace Bookings.Api.Contracts;

public sealed record AddTicketRequest(
    Guid FlightId,
    string PassengerId,
    string PassengerName,
    decimal Amount);
'@

Write-File "$bp/BookingsEndpoints.cs" @'
using Bookings.Api.Contracts;
using Bookings.Application.Commands.AddTicket;
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

        return app;
    }
}
'@

# ===========================================================================
# T-07, T-08: Tests
# ===========================================================================
Write-Host ""
Write-Host "=== T-07, T-08. Tests ==="

Write-File "$tests/Domain/BookingAddTicketTests.cs" @'
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingAddTicketTests
{
    private static Booking Make()
        => Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static PassengerId OtherPassenger() => PassengerId.Create("9999999999");
    private static PassengerName OtherName() => PassengerName.Create("PETROV PETR");

    [Fact]
    public void AddTicket_ToPendingBooking_SucceedsAndUpdatesTotal()
    {
        var booking = Make();
        booking.ClearDomainEvents();
        var flightId = Guid.NewGuid();

        var ticketId = booking.AddTicket(
            OtherPassenger(), OtherName(), flightId, 12500m);

        ticketId.Should().NotBeEmpty();
        booking.Tickets.Should().HaveCount(1);
        booking.TotalAmount.Amount.Should().Be(12500m);
        booking.TotalAmount.Currency.Should().Be("RUB");
        booking.DomainEvents.Should().ContainSingle(e => e is TicketAdded);
    }

    [Fact]
    public void AddTicket_Twice_SumsTotal()
    {
        var booking = Make();
        var flight1 = Guid.NewGuid();
        var flight2 = Guid.NewGuid();

        booking.AddTicket(OtherPassenger(), OtherName(), flight1, 10000m);
        booking.AddTicket(PassengerId.Create("5555555555"),
                          PassengerName.Create("SIDOROV S"),
                          flight2, 7500m);

        booking.TotalAmount.Amount.Should().Be(17500m);
    }

    [Fact]
    public void AddTicket_DuplicatePassengerOnSameFlight_Throws()
    {
        var booking = Make();
        var flightId = Guid.NewGuid();
        var passenger = OtherPassenger();

        booking.AddTicket(passenger, OtherName(), flightId, 10000m);

        var act = () => booking.AddTicket(passenger, OtherName(), flightId, 10000m);
        act.Should().Throw<DomainException>()
            .WithMessage("*already on flight*");
    }

    [Fact]
    public void AddTicket_SamePassengerOnDifferentFlights_Allowed()
    {
        var booking = Make();
        var passenger = OtherPassenger();

        booking.AddTicket(passenger, OtherName(), Guid.NewGuid(), 10000m);
        booking.AddTicket(passenger, OtherName(), Guid.NewGuid(), 10000m);

        booking.Tickets.Should().HaveCount(2);
    }

    [Fact]
    public void AddTicket_ZeroAmount_Throws()
    {
        var booking = Make();
        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 0m);
        act.Should().Throw<DomainException>().WithMessage("*must be positive*");
    }

    [Fact]
    public void AddTicket_NegativeAmount_Throws()
    {
        var booking = Make();
        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), -1m);
        act.Should().Throw<DomainException>().WithMessage("*must be positive*");
    }

    [Fact]
    public void AddTicket_EmptyFlightId_Throws()
    {
        var booking = Make();
        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.Empty, 100m);
        act.Should().Throw<DomainException>().WithMessage("*FlightId*");
    }

    [Fact]
    public void AddTicket_OnConfirmedBooking_Throws()
    {
        var booking = Make();
        booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 10000m);
        booking.Confirm();

        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 10000m);
        act.Should().Throw<DomainException>().WithMessage("*not Pending*");
    }

    [Fact]
    public void AddTicket_OnCancelledBooking_Throws()
    {
        var booking = Make();
        booking.Cancel("test");

        var act = () => booking.AddTicket(OtherPassenger(), OtherName(), Guid.NewGuid(), 10000m);
        act.Should().Throw<DomainException>().WithMessage("*not Pending*");
    }
}
'@

Write-File "$tests/Domain/BookingLifecycleTests.cs" @'
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.Events;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;
using FluentAssertions;
using Xunit;

namespace Bookings.UnitTests.Domain;

public class BookingLifecycleTests
{
    private static Booking Make() =>
        Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static void AddOneTicket(Booking b)
        => b.AddTicket(
            PassengerId.Create("9999999999"),
            PassengerName.Create("PETROV PETR"),
            Guid.NewGuid(),
            10000m);

    [Fact]
    public void Confirm_WithTickets_Succeeds()
    {
        var b = Make();
        AddOneTicket(b);
        b.ClearDomainEvents();

        b.Confirm();

        b.Status.Should().Be(BookingStatus.Confirmed);
        b.DomainEvents.Should().ContainSingle(e => e is BookingConfirmed);
    }

    [Fact]
    public void Confirm_WithoutTickets_Throws()
    {
        var b = Make();
        var act = () => b.Confirm();
        act.Should().Throw<DomainException>().WithMessage("*without tickets*");
    }

    [Fact]
    public void Confirm_OnAlreadyConfirmed_Throws()
    {
        var b = Make();
        AddOneTicket(b);
        b.Confirm();

        var act = () => b.Confirm();
        act.Should().Throw<DomainException>().WithMessage("*already confirmed*");
    }

    [Fact]
    public void MarkExpired_OnPending_Succeeds()
    {
        var b = Make();
        b.ClearDomainEvents();

        b.MarkExpired("payment failed");

        b.Status.Should().Be(BookingStatus.Expired);
        b.DomainEvents.Should().ContainSingle(e => e is BookingExpired);
    }

    [Fact]
    public void MarkExpired_OnConfirmed_Throws()
    {
        var b = Make();
        AddOneTicket(b);
        b.Confirm();

        var act = () => b.MarkExpired("late");
        act.Should().Throw<DomainException>().WithMessage("*Cannot expire*");
    }

    [Fact]
    public void MarkExpired_EmptyReason_Throws()
    {
        var b = Make();
        var act = () => b.MarkExpired("");
        act.Should().Throw<DomainException>().WithMessage("*reason*");
    }
}
'@

Write-File "$tests/Application/AddTicketCommandHandlerTests.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.Commands.AddTicket;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class AddTicketCommandHandlerTests
{
    private const int StatusScheduled = 0;
    private const int StatusCancelled = 4;

    private static Booking MakeBooking() =>
        Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static AddTicketCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<IFlightCatalogClient> fc)
        => new(repo.Object, uow.Object, fc.Object,
               NullLogger<AddTicketCommandHandler>.Instance);

    private static FlightSummary Summary(Guid id, int status = StatusScheduled)
        => new(id, "PG-0001", "SVO", "OVB",
               DateTimeOffset.UtcNow.AddDays(1),
               DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
               status);

    [Fact]
    public async Task Handle_HappyPath_ReturnsTicketId()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var handler = Build(repo, uow, fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "PETROV PETR", 12000m),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();
        booking.TotalAmount.Amount.Should().Be(12000m);
        uow.Verify(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_BookingNotFound_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Booking?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<IFlightCatalogClient>());

        var result = await handler.Handle(
            new AddTicketCommand(Guid.NewGuid(), Guid.NewGuid(), "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_FlightNotFound_ReturnsFailure()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((FlightSummary?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(), fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("flight_not_found");
    }

    [Fact]
    public async Task Handle_FlightCancelled_ReturnsFailure()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId, StatusCancelled));

        var handler = Build(repo, new Mock<IUnitOfWork>(), fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("flight_unavailable");
    }

    [Fact]
    public async Task Handle_DomainViolation_ReturnsDomainError()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        // First ticket added directly to make duplicate
        booking.AddTicket(
            PassengerId.Create("9999999999"),
            PassengerName.Create("PETROV PETR"),
            flightId,
            10000m);

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var handler = Build(repo, new Mock<IUnitOfWork>(), fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "PETROV PETR", 10000m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("domain_error");
    }
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
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  1. dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  2. Create a booking:"
Write-Host '     POST /bookings { "passengerId":"1234567890", "passengerName":"IVANOV IVAN", "currency":"RUB" }'
Write-Host "  3. Take the returned booking id, then add a ticket:"
Write-Host "     First create a flight via FlightCatalog (or reuse an existing flightId)."
Write-Host "     POST /bookings/{id}/tickets"
Write-Host '     { "flightId":"<guid>", "passengerId":"9999999999", "passengerName":"PETROV PETR", "amount":12000 }'
Write-Host "  4. GET /bookings/{id} - TotalAmount should be 12000, tickets list has one item."
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(bookings): phase 3.2.1 - AddTicket + IFlightCatalogClient"'
Write-Host "  git push"
Write-Host ""